class Quiz < ApplicationRecord
  belongs_to :user
  has_many :questions, -> { order(:position, :id) }, dependent: :destroy, inverse_of: :quiz
  has_many :invitations, dependent: :restrict_with_error
  has_many :exam_batches, dependent: :restrict_with_error

  accepts_nested_attributes_for :questions, allow_destroy: true, reject_if: ->(attrs) { attrs["body"].blank? }

  validates :title, presence: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 300 }
  validates :pass_percentage, numericality: { only_integer: true, in: 0..100 }
  validate :must_have_questions

  QUESTION_HEADERS = [ "Question", "Option A", "Option B", "Option C", "Option D", "Correct Answer (A/B/C/D)", "Marks" ].freeze
  ANSWER_COLUMNS = [ "correct answer", "correct option", "answer", "ans", "correct", "right answer", "answer key", "key" ].freeze
  TEMPLATE_NOTES = [
    "HOW TO FILL THE QUESTION SHEET",
    "1. One question per row. Keep the header row as it is.",
    "2. Fill at least Option A and Option B. Option C and D are optional.",
    "3. Correct Answer (green column) is REQUIRED - it is used to calculate the result.",
    "   You can write the letter (A / B / C / D), the number (1 / 2 / 3 / 4) or the exact option text (e.g. New Delhi).",
    "4. Marks: marks for a correct answer (defaults to 1 when blank). Wrong or skipped answers get 0.",
    "5. Save as .xlsx or .csv and upload it on the question paper form.",
    "",
    "RESULT: score = total marks of correctly answered questions. Percentage >= pass % of the paper means PASS."
  ].freeze

  # Builds questions from an uploaded sheet. Returns a list of row errors (empty on success).
  def import_questions(file)
    errors = []
    built = []
    next_position = questions.map { |q| q.position.to_i }.max.to_i
    Spreadsheet.rows(file).each do |line, row|
      body = row["question"].to_s.strip
      options = Question::LETTERS.map { |l| row["option #{l.downcase}"].to_s.strip }
      next if body.blank? && options.all?(&:blank?)

      answer = ANSWER_COLUMNS.lazy.map { |k| row[k] }.find(&:present?).to_s.strip
      correct = self.class.answer_index(answer, options)
      if body.blank? then errors << "Row #{line}: question text is missing"
      elsif options.count(&:present?) < 2 then errors << "Row #{line}: needs at least two options"
      elsif answer.blank? then errors << "Row #{line}: Correct Answer is empty — write A, B, C or D so the result can be calculated"
      elsif correct.nil? then errors << "Row #{line}: Correct Answer \"#{answer}\" doesn't match any option (use A-D or the exact option text)"
      else
        marks = row["marks"].to_i.positive? ? row["marks"].to_i : 1
        built << questions.build(body: body, options: options, correct_index: correct, marks: marks, position: next_position += 1)
      end
    end
    errors << "No questions found in the file" if errors.empty? && built.empty?
    built.each { |q| questions.delete(q) } if errors.any? # all-or-nothing, so a fixed re-upload doesn't duplicate rows
    errors
  rescue Spreadsheet::Error => e
    [ e.message ]
  end

  # "B", "b)", "2", "Option B" or the option's own text -> option index.
  def self.answer_index(answer, options)
    a = answer.to_s.strip
    return if a.blank?

    by_text = options.index { |o| o.present? && o.casecmp?(a) }
    return by_text if by_text

    letter = a.sub(/\Aoption\s*/i, "")[/\A([A-Fa-f])(\W|\z)/, 1]
    idx = letter ? Question::LETTERS.index(letter.upcase) : (a =~ /\A[1-6]\z/ ? a.to_i - 1 : nil)
    idx if idx && options[idx].present?
  end

  def self.question_template
    Spreadsheet.build("Questions", QUESTION_HEADERS, [
      [ "What is the capital of India?", "Mumbai", "New Delhi", "Kolkata", "Chennai", "B", "1" ],
      [ "2 + 2 x 2 = ?", "8", "6", "4", "", "B", "2" ]
    ], widths: [ 60, 22, 22, 22, 22, 18, 10 ], notes: TEMPLATE_NOTES, highlight: [ 5 ])
  end

  def questions_xlsx
    rows = questions.map do |q|
      opts = (q.options + [ "", "", "", "" ]).first(4)
      [ q.body, *opts, Question::LETTERS[q.correct_index], q.marks.to_s ]
    end
    Spreadsheet.build("Questions", QUESTION_HEADERS, rows, widths: [ 60, 22, 22, 22, 22, 18, 10 ], notes: TEMPLATE_NOTES, highlight: [ 5 ])
  end

  def total_marks
    questions.sum(&:marks)
  end

  private
    def must_have_questions
      errors.add(:base, "Add at least one question") if questions.reject(&:marked_for_destruction?).empty?
    end
end
