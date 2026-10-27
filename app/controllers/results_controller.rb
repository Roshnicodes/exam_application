class ResultsController < ApplicationController
  HEADERS = [ "Rank", "Candidate", "Email", "Mobile", "Vacancy", "Department", "Question paper", "Score", "Total marks",
              "Percentage", "Pass mark %", "Result", "Exam status", "Warnings", "Time taken (min)", "Submitted at",
              "Interview avg (/10)", "Panel recommendations", "Final selection score %", "Stages done" ].freeze

  def index
    load_results
    @page_results = paginate(@results) # ranks and the summary still cover everyone
  end

  def export
    load_results
    rows = @results.map do |i|
      [ @ranks[i.id], i.candidate_name, i.candidate_email, i.entered_phone.presence || i.candidate_phone, i.vacancy, i.department,
        i.quiz.title, i.score, i.total_marks, "#{i.percentage}%", "#{i.quiz.pass_percentage}%", i.result_label,
        i.terminated? ? "Terminated (#{i.termination_reason})" : "Submitted", i.warnings_count,
        i.time_taken ? (i.time_taken / 60.0).round(1) : "", i.submitted_at&.strftime("%d-%m-%Y %I:%M %p"),
        i.interview_average, i.interview_feedbacks.map { |f| "#{f.reviewer_name}: #{f.recommendation_label}" }.join("; "),
        @finals[i.id][:percent], "#{@finals[i.id][:done]}/#{@finals[i.id][:total]}" ].map(&:to_s)
    end
    send_xlsx Spreadsheet.build("Results", HEADERS, rows, widths: [ 7, 24, 28, 14, 26, 18, 26, 8, 11, 11, 11, 9, 28, 10, 14, 20, 14, 40, 16, 10 ], highlight: [ 9, 11, 16, 18 ]),
              "exam-results-#{Date.current}.xlsx"
  end

  private
    def load_results
      all = Current.user.invitations.completed.includes(:quiz, :interview_feedbacks)
      @quizzes = Current.user.quizzes.order(:title)
      @vacancies = all.distinct.order(:vacancy).pluck(:vacancy)

      scope = all
      scope = scope.where(quiz_id: params[:quiz_id]) if params[:quiz_id].present?
      scope = scope.where(vacancy: params[:vacancy]) if params[:vacancy].present?
      if params[:q].present?
        q = "%#{Invitation.sanitize_sql_like(params[:q])}%"
        scope = scope.where("candidate_name ILIKE :q OR candidate_email ILIKE :q", q: q)
      end

      results = scope.to_a
      results.select!(&:passed?) if params[:result] == "pass"
      results.reject!(&:passed?) if params[:result] == "fail"

      # rank within each question paper, by test score or by the weighted final score
      @sort = params[:sort] == "final" ? "final" : "test"
      @finals = all.to_a.index_by(&:id).transform_values(&:final_score)
      order = lambda do |i|
        primary = @sort == "final" ? (@finals[i.id][:percent] || -1) : i.percentage
        [ -primary, i.time_taken || Float::INFINITY ]
      end
      @ranks = all.to_a.group_by(&:quiz_id).flat_map do |_, list|
        list.sort_by(&order).each_with_index.map { |i, idx| [ i.id, idx + 1 ] }
      end.to_h
      @results = results.sort_by(&order)

      @summary = {
        total: results.size,
        passed: results.count(&:passed?),
        failed: results.count { |i| !i.passed? },
        average: results.any? ? (results.sum(&:percentage) / results.size.to_f).round : 0,
        top: results.map(&:percentage).max || 0
      }
    end
end
