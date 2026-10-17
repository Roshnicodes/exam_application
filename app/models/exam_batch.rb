# A group exam: one set of exam details shared by many candidates, each with their own link.
class ExamBatch < ApplicationRecord
  CANDIDATE_HEADERS = [ "Name", "Email", "Mobile", "Experience" ].freeze
  COLUMN_ALIASES = {
    candidate_name: [ "name", "candidate name", "full name", "candidate" ],
    candidate_email: [ "email", "email id", "candidate email" ],
    candidate_phone: [ "mobile", "mobile number", "phone", "contact", "contact number" ],
    experience: [ "experience", "exp" ]
  }.freeze

  attr_accessor :candidates_file # upload is read in the controller, this only feeds the form

  belongs_to :user
  belongs_to :quiz
  belongs_to :opening, class_name: "Vacancy", foreign_key: :vacancy_id, optional: true
  has_many :invitations, -> { order(:candidate_name) }, dependent: :destroy
  has_many :exam_batch_panelists, dependent: :destroy
  has_many :panelists, through: :exam_batch_panelists, source: :employee

  has_secure_token :watch_token, length: 24 # read-only live monitor link for panelists

  validates :name, presence: true
  validates :max_warnings, numericality: { only_integer: true, in: 0..50 }
  validates :interview_plan, inclusion: { in: Invitation::INTERVIEW_PLANS.keys }
  validate :vacancy_given
  validate :owned_by_user

  def panelist_ids=(ids)
    self.panelists = user.employees.where(id: Array(ids).compact_blank)
  end

  def post_name
    opening&.title || vacancy_title
  end

  def stats
    list = invitations.to_a
    { invited: list.size, live: list.count(&:in_progress?), waiting: list.count { |i| %w[pending otp_requested verified].include?(i.status) },
      finished: list.count(&:finished?), passed: list.count(&:passed?) }
  end

  # Merges the rows typed in the form with rows from an uploaded sheet.
  # Returns [ [ { candidate_name:, candidate_email:, candidate_phone:, experience: } ], errors ].
  def self.collect_candidates(form_rows, file)
    rows = Array(form_rows).map { |r| r.to_h.symbolize_keys.slice(*COLUMN_ALIASES.keys) }
    errors = []
    if file.present?
      Spreadsheet.rows(file).each do |_line, row|
        rows << COLUMN_ALIASES.transform_values { |keys| keys.lazy.map { |k| row[k] }.find(&:present?) }
      end
    end
    [ rows.reject { |r| r.values.all?(&:blank?) }, errors ]
  rescue Spreadsheet::Error => e
    [ [], [ e.message ] ]
  end

  # Builds one invitation per row (unsaved). Returns [invitations, errors].
  def build_invitations(rows)
    errors = []
    built = rows.each_with_index.map do |row, i|
      invitation = invitations.build(
        row.merge(user: user, quiz: quiz, opening: opening, vacancy: vacancy_title, department: department,
                  interview_date: interview_date, interview_mode: interview_mode, location: location, notes: notes,
                  max_warnings: max_warnings, link_expires_at: link_expires_at, meeting_link: meeting_link,
                  interview_plan: interview_plan)
      )
      errors << "Candidate #{i + 1} (#{row[:candidate_name].presence || 'no name'}): #{invitation.errors.full_messages.to_sentence}" unless invitation.valid?
      invitation
    end
    [ built, errors ]
  end

  SHARED_FIELDS = %i[interview_date interview_mode location notes max_warnings link_expires_at meeting_link].freeze

  # Pushes schedule / rule changes to candidates who haven't started yet.
  def sync_pending_invitations!
    invitations.where(started_at: nil).find_each do |i|
      i.update!(SHARED_FIELDS.index_with { |f| public_send(f) }.merge(opening: opening, vacancy: opening ? i.vacancy : vacancy_title))
    end
  end

  def links_xlsx(url_for_token)
    rows = invitations.map do |i|
      [ i.candidate_name, i.candidate_email, i.candidate_phone, url_for_token.call(i.token), i.status_label ].map(&:to_s)
    end
    Spreadsheet.build("Exam links", [ "Name", "Email", "Mobile", "Exam link", "Status" ], rows, widths: [ 26, 30, 14, 70, 16 ], highlight: [ 3 ])
  end

  private
    def vacancy_given
      errors.add(:base, "Choose a vacancy (or type the post name)") if opening.nil? && vacancy_title.blank?
    end

    def owned_by_user
      errors.add(:quiz, "is invalid") if quiz && quiz.user_id != user_id
      errors.add(:opening, "is invalid") if opening && opening.user_id != user_id
    end
end
