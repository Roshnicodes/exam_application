class QuizzesController < ApplicationController
  before_action :set_quiz, only: %i[show edit update destroy export hindi_upload translate]

  def index
    @quizzes = Current.user.quizzes.includes(:questions).order(created_at: :desc)
  end

  def show
    @lang = params[:lang] == "hi" ? "hi" : "en"
    @translation_result = Rails.cache.read("quiz:#{@quiz.id}:translation_result")
  end

  # A Hindi copy of the paper (Word / PDF / Excel / text, same order) fills the Hindi version.
  def hindi_upload
    filled, notes = @quiz.import_hindi(params[:file])
    message = "Hindi added to #{filled} of #{@quiz.questions.size} questions."
    message += " #{notes.first(3).join(' ')}" if notes.any?
    redirect_to quiz_path(@quiz, lang: "hi"), (filled.positive? ? { notice: message } : { alert: message })
  rescue QuestionPaperParser::Error => e
    redirect_to quiz_path(@quiz), alert: e.message
  end

  # Auto-translate the questions that don't have Hindi yet (Claude, in the background).
  def translate
    return redirect_to(quiz_path(@quiz), alert: "Auto-translation needs ANTHROPIC_API_KEY on the server. Upload a Hindi copy or type the Hindi instead.") unless HindiTranslator.available?

    Rails.cache.delete("quiz:#{@quiz.id}:translation_result")
    Rails.cache.write(@quiz.translation_key, true, expires_in: 30.minutes)
    TranslateQuizJob.perform_later(@quiz)
    redirect_to quiz_path(@quiz, lang: "hi"), notice: "Translating to Hindi… this page updates by itself."
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
    # Reads an uploaded paper (Word, PDF, Excel / CSV or text) into the form's questions.
    # Saves straight away only when every question already has its answer; otherwise the form comes
    # back for review with the questions that still need a correct option marked in red.
    def import_questions
      file = params.dig(:quiz, :questions_file)
      return true if file.blank?

      paper = QuestionPaperParser.parse(file)
      @quiz.title = paper.title if @quiz.title.blank? && paper.title.present?
      @quiz.duration_minutes = paper.duration if paper.duration.to_i.between?(1, 300) && @quiz.new_record?
      position = @quiz.questions.map { |q| q.position.to_i }.max.to_i
      paper.questions.each { |q| @quiz.questions.build(q.merge(position: position += 1)) }

      missing = paper.questions.count { |q| q[:correct_index].nil? }
      return true if missing.zero? && paper.warnings.empty?

      @import_review = { file: file.original_filename, count: paper.questions.size, missing: missing, warnings: paper.warnings }
      false
    rescue QuestionPaperParser::Error => e
      @import_errors = [ e.message ]
      false
    end

    def set_quiz
      @quiz = Current.user.quizzes.find(params[:id])
    end

    def quiz_params
      params.expect(quiz: [ :title, :description, :duration_minutes, :pass_percentage, :show_result_to_candidate,
                            questions_attributes: [ [ :id, :body, :body_hi, :correct_index, :marks, :position, :_destroy, options: [], options_hi: [] ] ] ])
    end
end
