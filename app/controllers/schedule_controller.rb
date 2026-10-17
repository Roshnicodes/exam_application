# Upcoming interview rounds across all candidates, day by day.
class ScheduleController < ApplicationController
  def index
    rounds = InterviewRound.joins(:invitation).where(invitations: { user_id: Current.user.id })
                           .includes(:invitation, :assigned_panelists).upcoming.to_a
    @live = rounds.select(&:open?)
    scheduled = rounds.reject(&:open?)
    @unscheduled = scheduled.reject(&:scheduled_at)
    @days = scheduled.select(&:scheduled_at).sort_by(&:scheduled_at).group_by { |r| r.scheduled_at.to_date }
  end
end
