# Demo HR account and sample question papers. Safe to run repeatedly.
hr = User.find_or_initialize_by(email_address: "hr@example.com")
hr.update!(name: "Priya Sharma", password: "password123") if hr.new_record?

papers = {
  "General Aptitude & Reasoning" => {
    description: "Quantitative aptitude, logical reasoning and verbal ability for all roles.",
    duration: 20, pass: 60,
    questions: [
      [ "A train travels 360 km in 4 hours. What is its average speed?", [ "80 km/h", "90 km/h", "100 km/h", "120 km/h" ], 1 ],
      [ "Find the next number in the series: 2, 6, 12, 20, 30, ?", [ "36", "40", "42", "44" ], 2 ],
      [ "If 5 workers finish a job in 12 days, how many days will 6 workers take?", [ "8", "9", "10", "11" ], 2 ],
      [ "Choose the word most opposite in meaning to 'ABUNDANT'.", [ "Plentiful", "Scarce", "Large", "Generous" ], 1 ],
      [ "A shopkeeper sells an item for ₹1,200 at a 20% profit. What was the cost price?", [ "₹960", "₹1,000", "₹1,040", "₹1,100" ], 1 ],
      [ "All roses are flowers. Some flowers fade quickly. Which conclusion is valid?", [ "All roses fade quickly", "Some roses fade quickly", "No rose fades quickly", "None of these follows" ], 3 ],
      [ "What is 15% of 240?", [ "32", "34", "36", "38" ], 2 ],
      [ "If CAT is coded as 3120, how is DOG coded?", [ "4157", "4158", "4147", "5157" ], 0 ]
    ]
  },
  "Ruby on Rails Developer" => {
    description: "Core Ruby, Rails conventions, ActiveRecord and web fundamentals.",
    duration: 25, pass: 65,
    questions: [
      [ "Which method returns a new array with the block's results for each element?", [ "each", "map", "select", "inject" ], 1 ],
      [ "What does `has_many :through` set up in ActiveRecord?", [ "A polymorphic association", "A many-to-many association via a join model", "A one-to-one association", "A self-join" ], 1 ],
      [ "Which command creates a new migration in Rails?", [ "rails new migration", "rails g migration", "rake db:new", "rails db:create" ], 1 ],
      [ "How do you prevent N+1 queries when loading posts with their comments?", [ "Post.all.comments", "Post.joins(:comments)", "Post.includes(:comments)", "Post.where(:comments)" ], 2 ],
      [ "What does `params.expect` (Rails 8) primarily help with?", [ "Caching", "Strong parameter filtering", "Routing", "Background jobs" ], 1 ],
      [ "Which HTTP verb does `resources` map to the `update` action?", [ "POST", "GET", "PATCH/PUT", "DELETE" ], 2 ],
      [ "In Ruby, which of these is falsy?", [ "0", "\"\" (empty string)", "[] (empty array)", "nil" ], 3 ],
      [ "What is Turbo Streams used for?", [ "Video streaming", "Delivering partial page updates over HTML", "Database replication", "Asset compression" ], 1 ]
    ]
  },
  "Frontend Developer (JS/CSS)" => {
    description: "JavaScript, browser APIs, CSS layout and accessibility.",
    duration: 20, pass: 60,
    questions: [
      [ "What does `typeof null` return in JavaScript?", [ "\"null\"", "\"object\"", "\"undefined\"", "\"number\"" ], 1 ],
      [ "Which CSS property creates a flexible layout along one axis?", [ "display: grid", "display: flex", "position: absolute", "float: left" ], 1 ],
      [ "Which keyword declares a block-scoped variable that cannot be reassigned?", [ "var", "let", "const", "static" ], 2 ],
      [ "What will `[1, 2, 3].map(n => n * 2)` return?", [ "[1, 2, 3]", "[2, 4, 6]", "6", "undefined" ], 1 ],
      [ "Which attribute improves image accessibility for screen readers?", [ "title", "src", "alt", "role" ], 2 ],
      [ "Which method stops an event from bubbling up the DOM?", [ "preventDefault()", "stopPropagation()", "halt()", "cancel()" ], 1 ],
      [ "What does `Promise.all` do if one promise rejects?", [ "Ignores it", "Rejects immediately", "Waits and resolves", "Retries it" ], 1 ]
    ]
  }
}

papers.each do |title, data|
  next if hr.quizzes.exists?(title: title)

  quiz = hr.quizzes.new(title: title, description: data[:description], duration_minutes: data[:duration], pass_percentage: data[:pass])
  data[:questions].each_with_index do |(body, options, correct), i|
    quiz.questions.build(body: body, options: options, correct_index: correct, marks: 1, position: i + 1)
  end
  quiz.save!
end

departments = {
  "Engineering" => "Anita Desai",
  "Human Resources" => "Vikram Singh",
  "Sales & Marketing" => "Neha Kapoor"
}.to_h { |name, head| [ name, hr.departments.find_or_create_by!(name: name) { |d| d.head_name = head } ] }

[
  [ "EMP001", "Anita Desai", "Engineering", "Engineering Manager" ],
  [ "EMP002", "Rohit Mehta", "Engineering", "Tech Lead" ],
  [ "EMP003", "Sneha Iyer", "Engineering", "Senior Developer" ],
  [ "EMP004", "Vikram Singh", "Human Resources", "HR Manager" ],
  [ "EMP005", "Pooja Nair", "Human Resources", "Talent Partner" ],
  [ "EMP006", "Neha Kapoor", "Sales & Marketing", "Sales Head" ],
  [ "EMP007", "Arjun Rao", "Engineering", "QA Lead" ],
  [ "EMP008", "Kavita Joshi", "Sales & Marketing", "Marketing Manager" ]
].each do |code, name, dept, designation|
  hr.employees.find_or_create_by!(employee_code: code) do |e|
    e.assign_attributes(name: name, department_name: dept, designation: designation,
                        email: "#{name.split.first.downcase}@company.com")
  end
end

unless hr.vacancies.exists?
  rails_dev = hr.vacancies.create!(
    department: departments["Engineering"], title: "Ruby on Rails Developer", code: "ENG/2026/014", positions: 3,
    issue_date: Date.current, end_date: 30.days.from_now.to_date, experience_required: "1-3 years",
    qualification: "B.Tech / MCA in Computer Science or equivalent",
    selection_parameters: [ { name: "Online test", weight: 30 }, { name: "Technical interview", weight: 50 }, { name: "HR interview", weight: 20 } ]
  )
  rails_dev.panelists = hr.employees.where(employee_code: %w[EMP001 EMP002 EMP004])

  sales = hr.vacancies.create!(
    department: departments["Sales & Marketing"], title: "Sales Executive", code: "SAM/2026/007", positions: 5,
    issue_date: Date.current, end_date: 21.days.from_now.to_date, experience_required: "Fresher",
    qualification: "Any graduate with good communication skills",
    selection_parameters: [ { name: "Aptitude test", weight: 40 }, { name: "Group discussion", weight: 30 }, { name: "Final interview", weight: 30 } ]
  )
  sales.panelists = hr.employees.where(employee_code: %w[EMP006 EMP008 EMP005])
end

puts "Seeded HR login: hr@example.com / password123 (#{hr.quizzes.count} question papers)"
