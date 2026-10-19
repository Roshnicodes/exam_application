class DashboardController < ApplicationController
  PENDING = %w[pending otp_requested verified].freeze

  def index
    invitations = Current.user.invitations
    rounds = InterviewRound.joins(:invitation).where(invitations: { user_id: Current.user.id })
    week = 6.days.ago.beginning_of_day..Time.current.end_of_day
    last_week = 13.days.ago.beginning_of_day...6.days.ago.beginning_of_day

    @cards = [
      card("Total Candidates", invitations.count, "users", "blue", invitations_path(group: "position"),
           daily(invitations.where(created_at: week), :created_at),
           invitations.where(created_at: week).count, invitations.where(created_at: last_week).count, "vs last 7 days"),
      card("Interviews Today", rounds.where(scheduled_at: Time.current.all_day).or(rounds.where(status: "open")).count,
           "calendar", "violet", schedule_path, daily(rounds.where(scheduled_at: week), :scheduled_at),
           rounds.where(scheduled_at: Time.current.all_day).count, rounds.where(scheduled_at: Date.yesterday.all_day).count, "vs yesterday"),
      card("Completed", invitations.completed.count, "check-circle", "green", results_path,
           daily(invitations.completed.where(submitted_at: week), :submitted_at),
           invitations.completed.where(submitted_at: week).count, invitations.completed.where(submitted_at: last_week).count, "vs last 7 days"),
      card("Pending", invitations.where(status: PENDING).count, "clock", "amber", invitations_path(status: "pending"),
           daily(invitations.where(status: PENDING, created_at: week), :created_at),
           invitations.where(status: PENDING, created_at: week).count, invitations.where(status: PENDING, created_at: last_week).count, "vs last 7 days")
    ]

    today = rounds.includes(:invitation).where(scheduled_at: Time.current.all_day).or(rounds.where(status: "open"))
                  .where.not(status: "cancelled").order(:scheduled_at).to_a
    @schedule_title = "Today's Schedule"
    if today.empty?
      today = rounds.includes(:invitation).upcoming.where(scheduled_at: Time.current..).order(:scheduled_at).limit(5).to_a
      @schedule_title = "Upcoming Interviews"
    end
    @schedule = today.first(5)

    @recent = invitations.includes(:quiz, :interview_rounds).recent.limit(6)
    @live = invitations.live.recent.first ||
            rounds.where(status: "open").includes(:invitation).first&.invitation
    @feed = ProctorEvent.where(invitation: invitations).where.not(kind: "snapshot")
                        .includes(:invitation).order(created_at: :desc).limit(4)
    @alerts_today = ProctorEvent.violations.where(invitation: invitations, created_at: Time.current.all_day).count
  end

  private
    def card(label, value, icon, tone, path, spark, now, before, note)
      change = before.zero? ? (now.positive? ? 100 : 0) : ((now - before) * 100.0 / before).round
      { label: label, value: value, icon: icon, tone: tone, path: path, spark: spark, change: change, note: note }
    end

    # Count per day over the last 7 days, oldest first (for the sparklines).
    def daily(scope, column)
      zone = ActiveRecord::Base.connection.quote(Time.zone.tzinfo.name)
      counts = scope.group(Arel.sql("DATE((#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{zone})")).count.transform_keys(&:to_date)
      (0..6).map { |i| counts[6.days.ago.to_date + i].to_i }
    end
end
