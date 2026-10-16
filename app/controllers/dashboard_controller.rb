class DashboardController < ApplicationController
  def index
    invitations = Current.user.invitations
    @stats = {
      total: invitations.count,
      live: invitations.live.count,
      completed: invitations.completed.count,
      alerts_today: ProctorEvent.violations.where(invitation: invitations, created_at: Time.current.all_day).count
    }
    @live = invitations.live.includes(:quiz).recent
    @recent = invitations.includes(:quiz).recent.limit(8)
    @upcoming = invitations.where(interview_date: Time.current..).order(:interview_date).limit(5)
    @feed = ProctorEvent.where(invitation: invitations).where.not(kind: "snapshot")
                        .includes(:invitation).order(created_at: :desc).limit(12)
  end
end
