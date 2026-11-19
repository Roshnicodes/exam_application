# A practical ("live") task the candidate works on instead of — or besides — the MCQ test:
# an Excel sheet, a Tally entry, a letter to draft in Word, a data-entry file, code…
# HR uploads the task file(s) here once and gives it to any candidate as an assessment round.
class Assessment < ApplicationRecord
  # kind => [ label, icon, suggested file types ]
  KINDS = {
    "excel"      => [ "Excel / Spreadsheet", "sheet", ".xlsx,.xls,.xlsm,.csv,.ods" ],
    "tally"      => [ "Tally / Accounting", "building", ".zip,.rar,.900,.001,.tsf,.xlsx,.pdf" ],
    "word"       => [ "Word / Letter drafting", "file", ".docx,.doc,.pdf,.odt,.txt" ],
    "typing"     => [ "Typing / Data entry", "id-card", ".docx,.txt,.xlsx,.csv,.pdf" ],
    "coding"     => [ "Coding / Technical", "code", ".zip,.txt,.py,.rb,.js,.java,.cpp,.c,.sql,.html,.css,.json" ],
    "design"     => [ "Design / Presentation", "sparkles", ".pptx,.ppt,.pdf,.png,.jpg,.jpeg,.psd,.ai,.zip" ],
    "case_study" => [ "Case study / Written answer", "edit", ".pdf,.docx,.doc,.txt,.jpg,.png" ],
    "other"      => [ "Other practical task", "target", "" ]
  }.freeze

  # Everything we are happy to accept back from a candidate (used when HR leaves the list empty).
  DEFAULT_EXTENSIONS = ".xlsx,.xls,.xlsm,.xlsb,.csv,.ods,.pdf,.doc,.docx,.odt,.txt,.rtf,.ppt,.pptx,.zip,.rar,.7z," \
                       ".jpg,.jpeg,.png,.gif,.webp,.900,.001,.tsf,.xml,.json,.sql,.py,.rb,.js,.java,.cpp,.c,.cs,.html,.css,.md".freeze
  MAX_FILE_SIZE = 50.megabytes
  MAX_FILES = 12 # task files, and uploads a candidate may send back

  belongs_to :user
  has_many :interview_rounds, dependent: :restrict_with_error
  has_many :invitations, dependent: :restrict_with_error
  has_many :exam_batches, dependent: :restrict_with_error
  has_many_attached :files # the task itself: the sheet / brief / data the candidate works on
  has_one_attached :answer_key # HR's answer key file (never shown to the candidate); read into answer_items

  normalizes :title, with: ->(v) { v.to_s.squish }
  normalizes :allowed_extensions, with: ->(v) { v.to_s.downcase.gsub(/\s+/, "") }

  validates :title, presence: true
  validates :description, presence: { message: "— write a short description of the task" }, length: { maximum: 200 }
  validates :kind, inclusion: { in: KINDS.keys }
  validates :duration_minutes, numericality: { only_integer: true, in: 1..600 }
  validates :max_marks, numericality: { only_integer: true, in: 1..10_000 }
  validates :pass_percentage, numericality: { only_integer: true, in: 0..100 }
  validates :max_warnings, numericality: { only_integer: true, in: 0..50 }
  validate :files_are_sane

  scope :ordered, -> { order(:title) }
  scope :active, -> { where(active: true) }

  # ---- Answer key: automatic marking of the candidate's answer sheet ----
  def answer_sheet?
    answer_items.present?
  end

  def key_total
    answer_items.sum { |i| i["marks"].to_f }
  end

  # Reads HR's uploaded key into questions (raises AnswerKey::Error when nothing usable is found).
  def read_answer_key!(file)
    self.answer_items = AnswerKey.parse(file)
    answer_key.attach(file)
    self.max_marks = key_total.ceil if key_total.positive? # the test is out of the key's total
  end

  # HR's corrections from the review table: kind, correct answer, marks per question.
  def update_answer_items(rows)
    by_id = rows.to_h { |r| [ r["id"].to_s, r ] }
    self.answer_items = answer_items.filter_map do |item|
      row = by_id[item["id"]]
      next item unless row
      next if row["remove"] == "1"

      kind = AnswerKey::KINDS.key?(row["kind"]) ? row["kind"] : item["kind"]
      marks = row["marks"].to_s.strip.match?(/\A\d+(\.\d+)?\z/) ? row["marks"].to_f : item["marks"]
      answer = row["answer"].to_s.strip
      answer = answer.upcase.first(1) if kind == "choice"
      item.merge("kind" => kind, "marks" => marks, "answer" => answer.presence,
                 "terms" => kind == "text" && row["model"].present? ? AnswerKey.terms_in(row["model"]).first(14) : item["terms"],
                 "model" => row.key?("model") ? row["model"].to_s.first(4000) : item["model"])
    end
    self.max_marks = key_total.ceil if key_total.positive?
  end

  def kind_label
    KINDS.dig(kind, 0) || "Practical task"
  end

  def kind_icon
    KINDS.dig(kind, 1) || "target"
  end

  def self.suggested_extensions(kind)
    KINDS.dig(kind.to_s, 2).presence || DEFAULT_EXTENSIONS
  end

  # What the candidate is allowed to upload back, as a list of ".ext".
  def extensions
    list = allowed_extensions.presence || DEFAULT_EXTENSIONS
    list.split(",").map { |e| e.strip.downcase }.compact_blank.map { |e| e.start_with?(".") ? e : ".#{e}" }.uniq
  end

  def accept_attribute
    extensions.join(",")
  end

  def accepts?(filename)
    ext = File.extname(filename.to_s).downcase
    ext.present? && extensions.include?(ext)
  end

  def used_count
    interview_rounds.count
  end

  private
    def files_are_sane
      return unless files.attached?

      errors.add(:files, "— keep it to #{MAX_FILES} files") if files.size > MAX_FILES
      files.each do |file|
        errors.add(:files, "“#{file.filename}” is larger than #{MAX_FILE_SIZE / 1.megabyte} MB") if file.byte_size > MAX_FILE_SIZE
      end
    end
end
