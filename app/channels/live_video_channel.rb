# WebRTC signaling for the live camera feed (like a video call, one-way).
# The candidate's browser sends its camera straight to each viewer (HR / panelist);
# this channel only relays the connection set-up messages (offer / answer / ICE).
#
#   candidate: { role: "candidate", token: <exam token> }       must hold a verified exam session
#   viewer:    { role: "viewer", invitation_id:, viewer_id:, watch_token: } HR owner or watch link
class LiveVideoChannel < ApplicationCable::Channel
  def subscribed
    @role = params[:role]
    case @role
    when "candidate"
      @invitation = Invitation.find_by(token: params[:token].to_s)
      return reject unless @invitation && candidate_verified?

      stream_from stream(:candidate)
      to_viewers(type: "candidate-ready")
    when "viewer"
      @invitation = Invitation.find_by(id: params[:invitation_id])
      @viewer_id = params[:viewer_id].to_s.first(64)
      return reject unless @invitation && @viewer_id.present? &&
                           @invitation.watchable_with?(user: current_user, watch_token: params[:watch_token])

      stream_from stream(:viewers)
      stream_from stream("viewer:#{@viewer_id}")
      hello
    else
      reject
    end
  end

  def unsubscribed
    return unless @invitation

    if @role == "candidate"
      to_viewers(type: "candidate-left")
    elsif @viewer_id
      to_candidate(type: "viewer-left", viewer_id: @viewer_id)
    end
  end

  # Viewer asks the candidate to (re)start a stream for it.
  def hello(_data = nil)
    to_candidate(type: "viewer-joined", viewer_id: @viewer_id) if @role == "viewer"
  end

  # Relays an SDP description or ICE candidate to the other side.
  def signal(data)
    payload = data["data"]
    return unless payload.is_a?(Hash)

    if @role == "candidate"
      ActionCable.server.broadcast(stream("viewer:#{data['to'].to_s.first(64)}"), { type: "signal", data: payload })
    else
      to_candidate(type: "signal", viewer_id: @viewer_id, data: payload)
    end
  end

  private
    def stream(suffix)
      "live_video:#{@invitation.id}:#{suffix}"
    end

    def to_candidate(message)
      ActionCable.server.broadcast(stream(:candidate), message)
    end

    def to_viewers(message)
      ActionCable.server.broadcast(stream(:viewers), message)
    end

    def candidate_verified?
      phone = connection.exam_session["exam_#{@invitation.token}"]
      phone.present? && phone == @invitation.entered_phone && @invitation.in_progress?
    end
end
