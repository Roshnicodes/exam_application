# Two-way video room for one interview round (candidate + HR + panelists), WebRTC mesh:
# every participant connects directly to every other one; this channel only relays
# join/leave notices and the offer / answer / ICE messages between them.
#
#   candidate: { token:, peer_id: }                                 verified exam session; joins the live round
#   HR:        { round_id:, peer_id: }                              logged-in owner
#   panelist:  { round_id:, peer_id:, watch_token:, name: }         holds the candidate's / batch's watch link
class InterviewChannel < ApplicationCable::Channel
  def subscribed
    @peer_id = params[:peer_id].to_s.first(64)
    return reject if @peer_id.blank?

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

    stream_from room
    stream_from peer_stream(@peer_id)
    ActionCable.server.broadcast(room, { type: "peer-joined", peer: me })
  end

  def unsubscribed
    ActionCable.server.broadcast(room, { type: "peer-left", peer_id: @peer_id }) if @round && @peer_id
  end

  # Relays an SDP description or ICE candidate to one participant.
  def signal(data)
    to = data["to"].to_s.first(64)
    return if to.blank? || !data["data"].is_a?(Hash)

    ActionCable.server.broadcast(peer_stream(to), { type: "signal", from: me, data: data["data"] })
  end

  # Mic / camera on-off so others can show the right icons.
  def media_state(data)
    ActionCable.server.broadcast(room, { type: "media-state", peer_id: @peer_id, mic: data["mic"] == true, cam: data["cam"] == true })
  end

  private
    def me
      { id: @peer_id, name: @name, role: @role }
    end

    def room
      "interview_round:#{@round.id}"
    end

    def peer_stream(peer_id)
      "interview_round:#{@round.id}:peer:#{peer_id}"
    end

    def candidate_verified?(invitation)
      phone = connection.exam_session["exam_#{invitation.token}"]
      phone.present? && phone == invitation.entered_phone
    end
end
