# Kanban board of every candidate by hiring stage.
class PipelineController < ApplicationController
  def index
    scope = Current.user.invitations.includes(:quiz, :opening, :interview_feedbacks, interview_rounds: :interview_feedbacks).recent
    scope = scope.where(vacancy: params[:vacancy]) if params[:vacancy].present?
    @columns = Invitation::PIPELINE.keys.index_with { [] }
    scope.each { |i| @columns[i.pipeline_stage] << i }
    @vacancies = Current.user.invitations.distinct.order(:vacancy).pluck(:vacancy)
  end
end
