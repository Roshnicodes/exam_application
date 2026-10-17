# Two-way video room for one interview round (candidate + HR + panelists), WebRTC mesh:
# every participant connects directly to every other one; this channel only relays
# join/leave notices and the offer / answer / ICE messages between them.
#
#   candidate: { token:, peer_id: }                                 verified exam session; joins the live round
#   HR:        { round_id:, peer_id: }                              logged-in owner
#   panelist:  { round_id:, peer_id:, watch_token:, name: }         holds the candidate's / batch's watch link
#
# With { test: true } the same room runs as a video call during the online test, one per candidate:
#   candidate: { test: true, token:, peer_id: }                     while the exam is in progress
#   HR / panelist: { test: true, invitation_id:, peer_id:, watch_token:, name: }
class InterviewChannel < ApplicationCable::Channel
  def subscribed
    @peer_id = params[:peer_id].to_s.first(64)
    return reject if @peer_id.blank?
    return subscribe_test_call if params[:test].present?

    if params[:token].present?
      invitation = Invitation.find_by(token: params[:token].to_s)
      @round = invitation&.current_round
      return reject unless @round && candidate_verified?(invitation)

      @role = "candidate"
      @name = invitation.candidate_name
    else
      @round = InterviewRound.includes(:invitation).find_by(id: params[:round_id])
      return reject unless @round && !@round.cancelled? &&
                           @round.invitation.watchable_with?(user: current_user, watch_token: params[:watch_token])

      # joining through a watch link always means "panelist", even if HR is logged in on that browser
      @role = params[:watch_token].blank? ? "hr" : "panelist"
      @name = @role == "hr" ? current_user.name : params[:name].to_s.squish.first(60).presence || "Panelist"
    end

    @invitation = @round.invitation
    @room = "interview_round:#{@round.id}"
    enter
  end

  def unsubscribed
    ActionCable.server.broadcast(room, { type: "peer-left", peer_id: @peer_id }) if @room && @peer_id
  end

  # Relays an SDP description or ICE candidate to one participant.
  def signal(data)
    to = data["to"].to_s.first(64)
    return if to.blank? || !data["data"].is_a?(Hash)

    ActionCable.server.broadcast(peer_stream(to), { type: "signal", from: me, data: data["data"] })
  end

  # Chat in the call (questions typed by the panel, answers from the candidate). Saved for HR to review.
  def chat(data)
    body = data["body"].to_s.strip.first(2000)
    return if body.blank?

    message = @invitation.call_messages.create!(interview_round: @round, sender_name: @name, sender_role: @role, body: body)
    ActionCable.server.broadcast(room, { type: "chat", message: message.as_chat, from: @peer_id })
  end

  # Mic / camera / presenting on-off so others can show the right icons and the presented screen.
  def media_state(data)
    ActionCable.server.broadcast(room, { type: "media-state", peer_id: @peer_id, mic: data["mic"] == true, cam: data["cam"] == true,
                                         screen: data["screen"] == true })
  end

  # Panel lets the candidate leave the room window (e.g. to code in an online editor) without
  # tab-switch / full-screen warnings. Their screen stays shared, so the panel still sees it.
  def allow_switch(data)
    return if @role == "candidate"

    on = data["on"] == true
    Rails.cache.write(switch_key, on, expires_in: 12.hours)
    ActionCable.server.broadcast(room, { type: "allow-switch", on: on, by: @name })
    @invitation.proctor_events.create!(kind: on ? "switching_allowed" : "switching_blocked", message: "By #{@name}",
                                       metadata: { round_id: @round&.id }.compact)
  end

  # Shared code editor: the whole text is sent (debounced) and saved for HR to review later.
  def code(data)
    pad = CodePad.find_or_initialize_by(invitation: @invitation, interview_round: @round)
    pad.content = data["content"].to_s.first(CodePad::MAX_LENGTH)
    pad.language = data["language"].to_s if CodePad::LANGUAGES.key?(data["language"].to_s)
    pad.save!
    ActionCable.server.broadcast(room, { type: "code", content: pad.content, language: pad.language, from: @peer_id, by: @name })
  end

  private
    def subscribe_test_call
      if params[:token].present?
        invitation = Invitation.find_by(token: params[:token].to_s)
        return reject unless invitation&.in_progress? && candidate_verified?(invitation)

        @role = "candidate"
        @name = invitation.candidate_name
      else
        invitation = Invitation.find_by(id: params[:invitation_id])
        return reject unless invitation && invitation.watchable_with?(user: current_user, watch_token: params[:watch_token])

        @role = params[:watch_token].blank? ? "hr" : "panelist"
        @name = @role == "hr" ? current_user.name : params[:name].to_s.squish.first(60).presence || "Panelist"
      end
      @invitation = invitation
      @room = "test_call:#{invitation.id}"
      enter
    end

    def enter
      stream_from room
      stream_from peer_stream(@peer_id)
      transmit({ type: "welcome", key: identity })
      ActionCable.server.broadcast(room, { type: "peer-joined", peer: me })
      transmit({ type: "allow-switch", on: true, by: nil }) if Rails.cache.read(switch_key)
      pad = CodePad.find_by(invitation: @invitation, interview_round: @round)
      transmit({ type: "code", content: pad.content, language: pad.language, from: nil, by: nil }) if pad&.content.present?
      history = @invitation.call_messages.where(interview_round: @round).last(100)
      mine = ->(m) { m.sender_name == @name && m.sender_role == @role }
      transmit({ type: "chat-history", messages: history.map { |m| m.as_chat.merge(mine: mine.(m)) } })
    end

    def me
      { id: @peer_id, name: @name, role: @role, key: identity }
    end

    # Same person joining again (refresh, second tab): the others replace the old tile instead of
    # showing them twice. Guest panelists share a name, so they are never merged.
    def identity
      case @role
      when "candidate" then "candidate"
      when "hr" then "hr:#{current_user.id}"
      else @name == "Guest panelist" ? nil : "panelist:#{@name.downcase}"
      end
    end

    def switch_key
      "allow_switch:#{room}"
    end

    def room
      @room
    end

    def peer_stream(peer_id)
      "#{@room}:peer:#{peer_id}"
    end

    def candidate_verified?(invitation)
      phone = connection.exam_session["exam_#{invitation.token}"]
      phone.present? && phone == invitation.entered_phone
    end
end
