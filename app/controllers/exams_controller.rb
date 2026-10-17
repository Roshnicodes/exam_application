# Public, token-addressed flow for candidates: phone + OTP verification, proctored exam, submission.
class ExamsController < ApplicationController
  allow_unauthenticated_access
  layout "exam"

  rate_limit to: 6, within: 5.minutes, only: :request_otp,
             with: -> { redirect_to exam_path(params[:token]), alert: "Too many OTP requests. Please wait a few minutes." }
  rate_limit to: 15, within: 5.minutes, only: :verify_otp,
             with: -> { redirect_to exam_path(params[:token]), alert: "Too many attempts. Please wait a few minutes." }

  before_action :set_invitation
  before_action :redirect_if_finished, except: %i[finished events recordings interview]
  before_action :require_verified, only: %i[instructions start take answer submit interview]
  before_action :auto_submit_if_time_up, only: %i[take answer submit]

  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.html { render :invalid, status: :not_found }
      format.any { head :not_found }
    end
  end

  def show
    return redirect_to exam_interview_path(@invitation.token) if @invitation.interview_open? && candidate_verified?
    return redirect_to exam_take_path(@invitation.token) if @invitation.in_progress? && candidate_verified?
    redirect_to exam_instructions_path(@invitation.token) if @invitation.verified? && candidate_verified?
  end

  def request_otp
    return redirect_to exam_path(@invitation.token), alert: "This exam link has expired. Please contact HR." if @invitation.link_expired?

    @invitation.request_otp!(params[:phone])
    redirect_to exam_path(@invitation.token, step: "otp"), notice: "OTP has been sent to HR. Please ask your HR for the 6 digit code."
  rescue ArgumentError => e
    redirect_to exam_path(@invitation.token), alert: e.message
  end

  def verify_otp
    @invitation.verify_otp!(params[:otp])
    session[session_key] = @invitation.entered_phone
    return redirect_to exam_interview_path(@invitation.token), notice: "Verified — joining the interview." if @invitation.interview_open?

    redirect_to exam_instructions_path(@invitation.token), notice: "Verified successfully!"
  rescue ArgumentError => e
    redirect_to exam_path(@invitation.token, step: "otp"), alert: e.message
  end

  def instructions
    redirect_to exam_take_path(@invitation.token) if @invitation.in_progress?
  end

  def start
    @invitation.start!
    redirect_to exam_take_path(@invitation.token)
  end

  def take
    return redirect_to exam_instructions_path(@invitation.token) unless @invitation.in_progress?

    @questions = @invitation.quiz.questions
  end

  def answer
    @invitation.save_answer!(params[:question_id], params[:option])
    render json: { ok: true, answered: @invitation.answered_count, seconds_left: @invitation.seconds_left }
  end

  def events
    return head :forbidden unless candidate_verified?
    return render json: { status: @invitation.status, terminated: true } if @invitation.finished?

    kind = params[:kind].to_s
    return head :unprocessable_entity unless ProctorEvent::KINDS.key?(kind)

    @invitation.record_event!(kind, message: params[:message].to_s.first(250).presence, snapshot: params[:snapshot])
    @invitation.reload
    render json: {
      status: @invitation.status,
      warnings: @invitation.warnings_count,
      max_warnings: @invitation.max_warnings,
      terminated: @invitation.finished?,
      redirect: (exam_finished_path(@invitation.token) if @invitation.finished?)
    }
  end

  def recordings
    return head :forbidden unless candidate_verified?
    return head :unprocessable_entity unless params[:segment].respond_to?(:content_type)

    @invitation.recordings.attach(io: params[:segment].tempfile, content_type: params[:segment].content_type,
                                  filename: "segment-#{params[:index].to_i.to_s.rjust(3, "0")}-#{Time.current.to_i}#{File.extname(params[:segment].original_filename.to_s).presence || ".webm"}")
    head :created
  end

  def submit
    @invitation.submit!(params.fetch(:answers, {}).permit!.to_h)
    redirect_to exam_finished_path(@invitation.token)
  end

  def finished
    redirect_to exam_path(@invitation.token) unless @invitation.finished?
  end

  # Two-way video interview with the panel: joins whichever round HR has made live.
  def interview
    @round = @invitation.current_round
    redirect_to exam_finished_path(@invitation.token), alert: "No interview round is live right now." unless @round
  end

  private
    def set_invitation
      @invitation = Invitation.includes(:quiz, :user).find_by!(token: params[:token])
    end

    def session_key
      "exam_#{@invitation.token}"
    end

    def candidate_verified?
      session[session_key].present? && session[session_key] == @invitation.entered_phone
    end
    helper_method :candidate_verified?

    def require_verified
      redirect_to exam_path(@invitation.token), alert: "Please verify your mobile number first." unless candidate_verified?
    end

    def redirect_if_finished
      return unless @invitation.finished?
      # a candidate on a new device may still need the OTP to join an open interview
      return if @invitation.interview_open? && action_name.in?(%w[show request_otp verify_otp])

      redirect_to exam_finished_path(@invitation.token)
    end

    def auto_submit_if_time_up
      return unless @invitation.time_up?

      @invitation.submit!(params.fetch(:answers, {}).permit!.to_h, reason: "time_up")
      respond_to do |format|
        format.html { redirect_to exam_finished_path(@invitation.token) }
        format.json { render json: { terminated: true, redirect: exam_finished_path(@invitation.token) } }
      end
    end
end
