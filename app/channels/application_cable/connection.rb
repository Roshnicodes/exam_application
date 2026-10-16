module ApplicationCable
  # HR users are identified by their login cookie. Candidates and panelists (no login) may
  # also connect; every channel checks its own permission (see HrAlertsChannel, LiveVideoChannel).
  class Connection < ActionCable::Connection::Base
    identified_by :current_user, :client_id

    def connect
      self.current_user = Session.find_by(id: cookies.signed[AUTH_COOKIE])&.user
      self.client_id = SecureRandom.uuid
    end

    # The candidate's Rails session (holds "exam_<token>" once they verified with the OTP).
    def exam_session
      @exam_session ||= cookies.encrypted[Rails.application.config.session_options[:key]] || {}
    end
  end
end
