class Vacancy < ApplicationRecord
  belongs_to :user
  belongs_to :department
  has_many :vacancy_panelists, dependent: :destroy
  has_many :panelists, through: :vacancy_panelists, source: :employee
  has_many :invitations, dependent: :nullify, inverse_of: :opening
  has_many :exam_batches, dependent: :nullify

  normalizes :title, :code, with: ->(v) { v.to_s.squish.presence }

  validates :title, presence: true
  validates :positions, numericality: { only_integer: true, greater_than: 0 }
  validate :end_after_issue
  validate :department_belongs_to_user

  before_validation :clean_selection_parameters

  scope :ordered, -> { order(issue_date: :desc, created_at: :desc) }
  scope :open, -> { where("end_date IS NULL OR end_date >= ?", Date.current) }

  def status
    return "upcoming" if issue_date&.future?
    return "closed" if end_date&.past?

    "open"
  end

  def label
    "#{title} · #{department.name}"
  end

  def total_weight
    selection_parameters.sum { |p| p["weight"].to_i }
  end

  # Accepts the panelist picker's list of employee ids, ignoring anything not owned by this HR.
  def panelist_ids=(ids)
    self.panelists = user.employees.where(id: Array(ids).compact_blank)
  end

  private
    def clean_selection_parameters
      self.selection_parameters = Array(selection_parameters).filter_map do |p|
        p = p.to_h.stringify_keys
        next if p["name"].blank?

        { "name" => p["name"].to_s.squish, "weight" => p["weight"].to_i }
      end
    end

    def end_after_issue
      errors.add(:end_date, "must be on or after the issue date") if issue_date && end_date && end_date < issue_date
    end

    def department_belongs_to_user
      errors.add(:department, "is invalid") if department && department.user_id != user_id
    end
end
