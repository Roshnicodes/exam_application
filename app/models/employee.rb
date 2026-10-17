class Employee < ApplicationRecord
  HEADERS = [ "Employee Code", "Name", "Email", "Phone", "Department", "Designation" ].freeze

  belongs_to :user
  has_many :vacancy_panelists, dependent: :destroy
  has_many :vacancies, through: :vacancy_panelists
  has_many :invitation_panelists, dependent: :destroy
  has_many :exam_batch_panelists, dependent: :destroy
  has_many :interview_feedbacks, dependent: :nullify
  has_many :interview_round_panelists, dependent: :destroy

  normalizes :employee_code, :name, :department_name, :designation, with: ->(v) { v.to_s.squish.presence }
  normalizes :email, with: ->(e) { e.to_s.strip.downcase.presence }

  validates :name, presence: true
  validates :employee_code, uniqueness: { scope: :user_id, case_sensitive: false }, allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true

  scope :ordered, -> { order(:name) }

  def self.search(q)
    return all if q.blank?

    like = "%#{sanitize_sql_like(q)}%"
    where("name ILIKE :q OR employee_code ILIKE :q OR email ILIKE :q OR department_name ILIKE :q OR designation ILIKE :q", q: like)
  end

  def subtitle
    [ employee_code, designation, department_name ].compact_blank.join(" · ")
  end

  # Accepted header spellings (lower-case) for each field, most specific first
  # (e.g. a sheet may have both "Name of Employee" and a manager's "Name" column).
  COLUMN_ALIASES = {
    employee_code: [ "employee code", "emp code", "code", "employee id", "emp id" ],
    name: [ "name of employee", "employee name", "full name", "name" ],
    email: [ "work email", "official email", "email", "email id" ],
    phone: [ "phone", "mobile", "mobile number", "mobile no", "contact number" ],
    department_name: [ "department", "dept" ],
    designation: [ "designation", "position", "role" ]
  }.freeze

  # Upserts employees from every sheet of an uploaded file, matching on employee code (or email).
  # Later sheets win when the same employee appears twice. Returns { created:, updated:, errors: [] }.
  def self.import(user, file)
    result = { created: 0, updated: 0, errors: [] }
    Spreadsheet.sheets(file).each do |sheet_name, rows|
      next unless rows.first&.last&.keys&.intersect?(COLUMN_ALIASES[:name]) # skip sheets without a name column

      rows.each do |line, row|
        attrs = COLUMN_ALIASES.transform_values { |keys| keys.lazy.map { |k| row[k] }.find(&:present?) }
        next if attrs.values.all?(&:blank?)

        attrs[:email] = nil unless attrs[:email].to_s.match?(URI::MailTo::EMAIL_REGEXP)
        code = attrs[:employee_code].to_s.squish.presence
        email = attrs[:email].to_s.downcase.presence
        employee = (code && user.employees.where("LOWER(employee_code) = ?", code.downcase).first) ||
                   (email && !code && user.employees.find_by(email: email)) || user.employees.new
        new_record = employee.new_record?
        employee.assign_attributes(new_record ? attrs : attrs.compact_blank) # blank cells keep existing data
        if employee.save
          result[new_record ? :created : :updated] += 1
        else
          result[:errors] << "#{sheet_name} row #{line}: #{employee.errors.full_messages.to_sentence}"
        end
      end
    end
    result
  end
end
