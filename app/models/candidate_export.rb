# Everything HR may need about a set of candidates, as one Excel workbook:
# details + result, a summary per position, every warning, interview scores, answers and call chat.
class CandidateExport
  TIME = "%d-%m-%Y %I:%M %p".freeze

  # link: builds a candidate's test link (the controller passes one that knows the site's address)
  def initialize(invitations, link: ->(_invitation) { nil })
    @link = link
    @invitations = invitations.includes({ quiz: :questions }, :assigned_panelists, :opening, interview_rounds: :assigned_panelists,
                                        interview_feedbacks: :interview_round).to_a
  end

  def to_xlsx
    Spreadsheet.build_book([ candidates, positions, warnings, interview_scores, answers, chat ])
  end

  private
    def fmt(time)
      time&.strftime(TIME)
    end

    def candidates
      headers = [ "Candidate", "Email", "Mobile (HR)", "Mobile (entered)", "Experience", "Position", "Department", "Invited for",
                  "Question paper", "Invited on", "Link valid till", "Status", "Test started", "Test submitted", "Time taken (min)",
                  "Score", "Total marks", "Pass mark %", "Result", "Warnings", "Terminated because", "Interview rounds",
                  "Interview avg (/10)", "Final selection score %", "Decision", "Decision note", "Panel", "Interview date",
                  "Interview mode", "Meeting link", "Location", "Notes", "Test link" ]
      rows = @invitations.map do |i|
        [ i.candidate_name, i.candidate_email, i.candidate_phone, i.entered_phone, i.experience, i.vacancy, i.department, i.invited_for,
          i.quiz.title, fmt(i.created_at), fmt(i.link_expires_at), i.status_label, fmt(i.started_at), fmt(i.submitted_at),
          i.time_taken && (i.time_taken / 60.0).round(1), (i.score if i.finished?), (i.total_marks if i.finished?), i.quiz.pass_percentage,
          i.finished? ? (i.passed? ? "Qualified" : "Disqualified") : "Not taken", i.warnings_count, i.termination_reason,
          i.interview_rounds.map { |r| "#{r.name}: #{r.status_label}" }.join("; "), i.interview_average, i.final_score[:percent],
          i.decision_label, i.decision_note, i.panelists.map(&:name).join(", "),
          (fmt(i.interview_date) unless i.test_only?), (i.interview_mode unless i.test_only?), i.meeting_link, i.location, i.notes,
          @link.(i) ]
      end
      { name: "Candidates", headers: headers, rows: rows, highlight: [ 18 ],
        widths: [ 22, 26, 14, 14, 12, 24, 16, 15, 24, 18, 18, 14, 18, 18, 10, 8, 8, 8, 13, 9, 26, 34, 10, 10, 12, 26, 28, 18, 12, 30, 22, 30, 50 ] }
    end

    def positions
      rows = @invitations.group_by { |i| i.vacancy.presence || "No position" }.sort.map do |position, list|
        done = list.select(&:finished?)
        [ position, list.size, done.size, done.count(&:passed?), done.count { |i| !i.passed? },
          list.count { |i| i.decision == "selected" }, list.count { |i| i.decision == "on_hold" }, list.count { |i| i.decision == "rejected" } ]
      end
      { name: "By position", headers: [ "Position", "Invited", "Test taken", "Qualified", "Disqualified", "Selected", "On hold", "Rejected" ],
        rows: rows, widths: [ 30, 10, 11, 11, 13, 10, 10, 10 ], highlight: [ 3 ] }
    end

    def warnings
      rows = ProctorEvent.violations.where(invitation_id: @invitations.map(&:id)).includes(:invitation).order(:created_at).map do |e|
        [ e.invitation.candidate_name, e.invitation.vacancy, fmt(e.created_at), e.label, e.severity.capitalize, e.message ]
      end
      { name: "Warnings", headers: [ "Candidate", "Position", "Time", "Warning", "Severity", "Details" ],
        rows: rows, widths: [ 22, 24, 20, 38, 10, 50 ] }
    end

    def interview_scores
      rows = @invitations.flat_map do |i|
        i.interview_feedbacks.map do |f|
          [ i.candidate_name, i.vacancy, f.interview_round&.name, f.reviewer_name, f.recommendation_label, f.average,
            f.scores.map { |k, v| "#{k}: #{v}/10" }.join("; "), f.comments, fmt(f.updated_at) ]
        end
      end
      { name: "Interview scores", headers: [ "Candidate", "Position", "Round", "Panelist", "Recommendation", "Average (/10)", "Scores", "Comments", "Scored at" ],
        rows: rows, widths: [ 22, 24, 20, 22, 16, 12, 40, 50, 20 ] }
    end

    def answers
      rows = @invitations.select(&:finished?).flat_map do |i|
        i.quiz.questions.each_with_index.map do |q, n|
          picked = i.answers[q.id.to_s]
          [ i.candidate_name, i.vacancy, n + 1, q.body, picked.nil? ? "Skipped" : "#{Question::LETTERS[picked]}. #{q.options[picked]}",
            "#{Question::LETTERS[q.correct_index]}. #{q.correct_option}", picked.nil? ? "Skipped" : (q.correct?(picked) ? "Correct" : "Wrong"),
            q.correct?(picked) ? q.marks : 0 ]
        end
      end
      { name: "Answers", headers: [ "Candidate", "Position", "Q no.", "Question", "Answered", "Correct answer", "Result", "Marks" ],
        rows: rows, widths: [ 22, 24, 7, 60, 30, 30, 10, 7 ], highlight: [ 6 ] }
    end

    def chat
      rows = CallMessage.where(invitation_id: @invitations.map(&:id)).includes(:invitation, :interview_round).chronological.map do |m|
        [ m.invitation.candidate_name, m.interview_round&.name || "Online test call", fmt(m.created_at), m.sender_name,
          CallMessage::ROLES[m.sender_role], m.body ]
      end
      { name: "Call chat", headers: [ "Candidate", "Call", "Time", "From", "Role", "Message" ], rows: rows, widths: [ 22, 20, 20, 20, 11, 70 ] }
    end
end
