class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  # order matters: children that reference quizzes / vacancies go first
  has_many :invitations, dependent: :destroy
  has_many :exam_batches, dependent: :destroy
  has_many :quizzes, dependent: :destroy
  has_many :vacancies, dependent: :destroy
  has_many :departments, dependent: :destroy
  has_many :employees, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 6 }, allow_nil: true

  def initials
    name.to_s.split.map(&:first).first(2).join.upcase.presence || "HR"
  end

  def first_name
    name.to_s.split.first
  end
end
