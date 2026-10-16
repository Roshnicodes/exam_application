class QuizzesController < ApplicationController
  before_action :set_quiz, only: %i[show edit update destroy export]

  def index
    @quizzes = Current.user.quizzes.includes(:questions).order(created_at: :desc)
  end

  def show
  end

  def new
    @quiz = Current.user.quizzes.new
    @quiz.questions.build(options: [ "", "", "", "" ])
  end

  def create
    @quiz = Current.user.quizzes.new(quiz_params)
    if import_questions && @quiz.save
      redirect_to @quiz, notice: "Question paper created with #{@quiz.questions.size} questions."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @quiz.assign_attributes(quiz_params)
    if import_questions && @quiz.save
      redirect_to @quiz, notice: "Question paper updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @quiz.destroy
      redirect_to quizzes_path, notice: "Question paper deleted."
    else
      redirect_to @quiz, alert: "This paper is already used in candidate invitations and cannot be deleted."
    end
  end

  def template
    send_xlsx Quiz.question_template, "question_paper_template.xlsx"
  end

  def export
    send_xlsx @quiz.questions_xlsx, "#{@quiz.title.parameterize}-questions.xlsx"
  end

  private
    # Adds questions from the optional Excel/CSV upload. Returns false (with errors) when rows are invalid.
    def import_questions
      file = params.dig(:quiz, :questions_file)
      return true if file.blank?

      row_errors = @quiz.import_questions(file)
      return true if row_errors.empty?

      @import_errors = row_errors
      false
    end

    def set_quiz
      @quiz = Current.user.quizzes.find(params[:id])
    end

    def quiz_params
      params.expect(quiz: [ :title, :description, :duration_minutes, :pass_percentage, :show_result_to_candidate,
                            questions_attributes: [ [ :id, :body, :correct_index, :marks, :position, :_destroy, options: [] ] ] ])
    end
end
