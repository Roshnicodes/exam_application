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

  after_update :carry_settings_to_rounds

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

  PAPER_EXTENSIONS = %w[.docx .pdf .txt].freeze

  # ---- A task file's text ----
  # A Word / PDF / text task file is read for its questions. The candidate always gets the file
  # exactly as HR uploaded it; answers found in it ("Q1 – (b)", "Answer: B", a key table) are only
  # pointed out to HR.
  #   => nil (not readable) or { "lines" => [...] (all of it), "clean" => [...] (without answers),
  #                              "answers" => true when answers were found, "key_only" => true when it is only a key }
  def self.paper_view(attachment)
    return unless PAPER_EXTENSIONS.include?(attachment.filename.extension_with_delimiter.downcase)

    Rails.cache.fetch([ "paper-view", 4, attachment.blob.checksum ]) do
      lines = file_lines(attachment)
      check = QuestionPaper.candidate_view(lines)
      { "lines" => lines, "clean" => check["lines"], "answers" => check["removed"], "key_only" => check["key_only"] }
    end
  rescue QuestionPaperParser::Error, Zip::Error, ArgumentError, ActiveStorage::FileNotFoundError => e
    Rails.logger.warn("Could not read task file #{attachment.filename}: #{e.message}")
    nil
  end

  def self.file_lines(attachment)
    attachment.blob.open do |tmp|
      QuestionPaperParser.new(ActionDispatch::Http::UploadedFile.new(tempfile: tmp, filename: attachment.filename.to_s)).lines
    end
  end

  def paper_view(attachment)
    self.class.paper_view(attachment)
  end

  # The question paper among the task files (the first Word / PDF / text file with text in it).
  def paper_file
    files.attachments.find { |f| paper_view(f)&.dig("lines")&.any?(&:present?) }
  end

  # Puts each question's text (and MCQ options) from the question paper next to the answer key's
  # questions, so the candidate's answer sheet shows the question right above the answer.
  def read_paper!
    file = paper_file
    return if answer_items.blank? || file.nil?

    view = paper_view(file)
    paper = QuestionPaper.extract(view["clean"].presence || view["lines"])

    items = answer_items.map do |item|
      parent = item["id"][/\Aq\d+/]
      whole = paper[parent]
      own = paper[item["id"]]
      # "(a) Output tax" lines without marks are read as MCQ options; for a written question they are its parts
      if whole && item["kind"] != "choice" && Array(whole["options"]).any?
        parts = whole["options"].each_with_index.map { |o, i| "(#{(97 + i).chr}) #{o}" }
        own ||= { "text" => parts[item["id"].delete_prefix(parent).ord - 97] } if item["id"] != parent && item["id"].length == parent.length + 1
        whole = whole.merge("text" => [ whole["text"], *parts ].join("\n"), "options" => [])
      end
      own = nil if own && own["text"].blank?
      context = (whole["text"].split(/\n(?=\([a-z]\))/).first if own && item["id"] != parent && whole)
      found = own || whole
      next item.except("question", "context", "options") unless found

      item.merge("question" => found["text"], "context" => context, "options" => item["kind"] == "choice" ? Array(found["options"]).first(5).presence : nil).compact
    end
    update_columns(answer_items: items)
  rescue QuestionPaperParser::Error, Zip::Error, ArgumentError => e
    Rails.logger.warn("Could not read the question paper of assessment #{id}: #{e.message}")
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
    # Rounds made earlier kept a copy of the time / marks / warning limit. When HR changes them
    # here, rounds not yet submitted that still have the old copy follow (a value HR set for one
    # candidate on purpose — different from the old one — is left alone).
    def carry_settings_to_rounds
      { "max_warnings" => :max_warnings, "duration_minutes" => :duration_minutes, "max_marks" => :max_marks }.each do |attr, column|
        next unless saved_change_to_attribute?(attr)

        old_value, new_value = saved_change_to_attribute(attr)
        interview_rounds.where(submitted_at: nil, column => old_value).update_all(column => new_value, updated_at: Time.current)
      end
    end

    def files_are_sane
      return unless files.attached?

      errors.add(:files, "— keep it to #{MAX_FILES} files") if files.size > MAX_FILES
      files.each do |file|
        errors.add(:files, "“#{file.filename}” is larger than #{MAX_FILE_SIZE / 1.megabyte} MB") if file.byte_size > MAX_FILE_SIZE
      end
    end
end
