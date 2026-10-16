class Department < ApplicationRecord
  belongs_to :user
  has_many :vacancies, dependent: :restrict_with_error

  normalizes :name, :head_name, with: ->(v) { v.to_s.squish.presence }

  validates :name, presence: true, uniqueness: { scope: :user_id, case_sensitive: false }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  # Short badge text: "Human Resources" -> "HR", "Engineering" -> "EN"
  def initials
    words = name.to_s.scan(/[[:alnum:]]+/)
    (words.size > 1 ? words.first(2).map(&:first).join : name.to_s.first(2)).upcase
  end

  def open_vacancies_count
    vacancies.count { |v| v.status == "open" }
  end
end
