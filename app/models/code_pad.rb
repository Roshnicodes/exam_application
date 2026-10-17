# The shared code editor of one video call: the candidate writes code, the panel watches (and can type too).
class CodePad < ApplicationRecord
  LANGUAGES = { "plaintext" => "Plain text", "javascript" => "JavaScript", "python" => "Python", "java" => "Java",
                "ruby" => "Ruby", "cpp" => "C / C++", "csharp" => "C#", "php" => "PHP", "go" => "Go", "sql" => "SQL",
                "html" => "HTML / CSS" }.freeze
  MAX_LENGTH = 50_000

  belongs_to :invitation
  belongs_to :interview_round, optional: true

  validates :language, inclusion: { in: LANGUAGES.keys }
  validates :content, length: { maximum: MAX_LENGTH }

  def language_name
    LANGUAGES[language]
  end
end
