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

  private
    # Drop blank options while keeping the correct answer pointing at the same text.
    def compact_options
      raw = Array(options).map { |o| o.to_s.strip }
      correct_text = raw[correct_index] if correct_index
      self.options = raw.reject(&:blank?)
      self.correct_index = options.index(correct_text) || correct_index if correct_text
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
