# HR's library of practical ("live") assessments: an Excel sheet, a Tally entry, a Word letter,
# a data-entry file, a coding task… Uploaded once here, then given to any candidate as a round.
class AssessmentsController < ApplicationController
  before_action :set_assessment, only: %i[show edit update destroy duplicate]

  def index
    @assessments = Current.user.assessments.ordered.with_attached_files
  end

  def show
    @rounds = @assessment.interview_rounds.includes(:invitation).order(created_at: :desc).limit(25)
  end

  def new
    @assessment = Current.user.assessments.new(kind: params[:kind].presence_in(Assessment::KINDS.keys) || "excel",
                                               duration_minutes: 45, max_marks: 100, pass_percentage: 50, max_warnings: 5,
                                               allow_app_switch: true)
  end

  def create
    @assessment = Current.user.assessments.new(assessment_params)
    attach_files
    if @assessment.save
      redirect_to @assessment, notice: "Practical assessment “#{@assessment.title}” saved. Give it to a candidate from their round list or a new invite."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @assessment.assign_attributes(assessment_params)
    purge_files
    attach_files
    if @assessment.save
      redirect_to @assessment, notice: "“#{@assessment.title}” updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Same task with another name / file — handy for "Excel test – Level 2".
  def duplicate
    copy = Current.user.assessments.new(@assessment.attributes.except("id", "created_at", "updated_at"))
    copy.title = "#{@assessment.title} (copy)"
    copy.description = @assessment.description.presence || @assessment.kind_label # older tasks had none
    copy.save!
    @assessment.files.each { |file| copy.files.attach(file.blob) }
    redirect_to edit_assessment_path(copy), notice: "Copied. Change what you need and save."
  end

  def destroy
    if @assessment.destroy
      redirect_to assessments_path, notice: "Assessment deleted.", status: :see_other
    else
      redirect_to @assessment, alert: "This assessment is already given to candidates, so it cannot be deleted. Untick “Active” to stop offering it."
    end
  end

  private
    def set_assessment
      @assessment = Current.user.assessments.find(params[:id])
    end

    # New uploads are added to the files already there (assigning would replace them).
    def attach_files
      list = Array(params.dig(:assessment, :files)).select { |f| f.respond_to?(:original_filename) }
      @assessment.files.attach(list) if list.any?
    end

    # Ticked files are removed.
    def purge_files
      Array(params[:remove_files]).compact_blank.each do |id|
        @assessment.files.attachments.find { |a| a.id == id.to_i }&.purge_later
      end
    end

    def assessment_params
      params.expect(assessment: [ :title, :kind, :description, :instructions, :duration_minutes, :max_marks, :pass_percentage,
                                  :max_warnings, :allow_download, :require_upload, :allow_notes, :allowed_extensions, :active,
                                  :allow_app_switch, :online_sheet ])
    end
end
