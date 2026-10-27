# Live grid of the candidates writing a test right now, and a page of the tests already finished.
class MonitorController < ApplicationController
  before_action { Invitation.submit_overdue! } # time over but never submitted: finish them first

  def index
    invitations = Current.user.invitations
    @invitations = invitations.live.includes(:quiz)
    @getting_ready = invitations.where(status: %w[otp_requested verified]).where(updated_at: 1.day.ago..).order(:updated_at)
    @completed_count = invitations.completed.where(submitted_at: Time.current.all_day).count
  end

  PERIODS = { "today" => "Today", "yesterday" => "Yesterday", "week" => "Last 7 days", "month" => "Last 30 days", "all" => "All time" }.freeze

  def completed
    @period = PERIODS.key?(params[:period]) ? params[:period] : "today"
    @batches = Current.user.exam_batches.order(created_at: :desc)
    @batch = @batches.find_by(id: params[:batch_id])
    scope = Current.user.invitations.completed.includes(:quiz, :exam_batch)
    scope = scope.where(submitted_at: period_range) unless @period == "all"
    scope = scope.where(exam_batch: @batch) if @batch
    if params[:q].present?
      q = "%#{Invitation.sanitize_sql_like(params[:q])}%"
      scope = scope.where("candidate_name ILIKE :q OR vacancy ILIKE :q", q: q)
    end
    plain = scope.except(:includes)
    @stats = { total: plain.count, qualified: plain.qualified.count, terminated: plain.where(status: "terminated").count }
    @invitations = paginate(scope.order(submitted_at: :desc), per: 48).to_a
    @live_count = Current.user.invitations.live.count
  end

  private
    def period_range
      case @period
      when "yesterday" then Date.yesterday.all_day
      when "week" then 6.days.ago.beginning_of_day..
      when "month" then 29.days.ago.beginning_of_day..
      else Time.current.all_day
      end
    end
end
