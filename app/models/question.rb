class Question < ApplicationRecord
  LETTERS = %w[A B C D E F].freeze

  belongs_to :quiz

  before_validation :compact_options

  validates :body, presence: true
  validates :marks, numericality: { only_integer: true, greater_than: 0 }
  validate :options_are_valid

  def correct_option
    options[correct_index]
  end

  def correct?(answer_index)
    answer_index.present? && answer_index.to_i == correct_index
  end

  # ---- Hindi version (the candidate sees it when their test language is Hindi; answers use the same index)
  def hindi?
    body_hi.present? && options_hi.size == options.size && options_hi.all?(&:present?)
  end

  def text_in(language)
    language == "hi" && hindi? ? body_hi : body
  end

  def options_in(language)
    language == "hi" && hindi? ? options_hi : options
  end

  private
    # Drop blank options while keeping the correct answer pointing at the same text.
    def compact_options
      raw = Array(options).map { |o| o.to_s.strip }
      raw_hi = Array(options_hi).map { |o| o.to_s.strip }
      kept = raw.each_index.select { |i| raw[i].present? }
      self.correct_index = kept.index(correct_index) || correct_index if correct_index && raw[correct_index].present?
      self.options = kept.map { |i| raw[i] }
      self.options_hi = raw_hi.any?(&:present?) ? kept.map { |i| raw_hi[i].to_s } : [] # Hindi options stay aligned with A, B, C…
      self.body_hi = body_hi.to_s.strip.presence
    end

    def options_are_valid
      errors.add(:options, "need at least two choices") if options.size < 2
      if correct_index.nil?
        errors.add(:base, "— choose the correct answer for “#{body.to_s.truncate(60)}”")
      elsif !correct_index.between?(0, options.size - 1)
        errors.add(:correct_index, "must point at a filled option")
      end
    end
end
