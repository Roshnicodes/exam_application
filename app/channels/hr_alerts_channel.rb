class HrAlertsChannel < ApplicationCable::Channel
  def subscribed
    current_user ? stream_for(current_user) : reject
  end

  def self.notify(event)
    invitation = event.invitation
    routes = Rails.application.routes.url_helpers

    broadcast_to invitation.user, {
      id: event.id,
      kind: event.kind,
      severity: event.severity,
      title: event.label,
      message: event.message,
      candidate: invitation.candidate_name,
      vacancy: invitation.vacancy,
      invitation_id: invitation.id,
      otp: (invitation.otp_code if event.kind == "otp_requested"),
      warnings: invitation.warnings_count,
      max_warnings: invitation.max_warnings,
      url: routes.invitation_path(invitation),
      snapshot_url: (routes.rails_blob_path(event.snapshot, only_path: true) if event.snapshot.attached?),
      at: event.created_at.iso8601
    }
  end
end
