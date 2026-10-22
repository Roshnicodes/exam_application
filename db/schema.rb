# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_22_061807) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "call_messages", force: :cascade do |t|
    t.bigint "invitation_id", null: false
    t.bigint "interview_round_id"
    t.string "sender_name", null: false
    t.string "sender_role", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interview_round_id"], name: "index_call_messages_on_interview_round_id"
    t.index ["invitation_id"], name: "index_call_messages_on_invitation_id"
  end

  create_table "code_pads", force: :cascade do |t|
    t.bigint "invitation_id", null: false
    t.bigint "interview_round_id"
    t.string "language", default: "plaintext", null: false
    t.text "content", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["interview_round_id"], name: "index_code_pads_on_interview_round_id"
    t.index ["invitation_id", "interview_round_id"], name: "index_code_pads_on_invitation_id_and_interview_round_id", unique: true
    t.index ["invitation_id"], name: "index_code_pads_on_invitation_id"
  end

  create_table "departments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name", null: false
    t.string "head_name"
    t.text "description"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "name"], name: "index_departments_on_user_id_and_name", unique: true
    t.index ["user_id"], name: "index_departments_on_user_id"
  end

  create_table "employees", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "employee_code"
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.string "department_name"
    t.string "designation"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "employee_code"], name: "index_employees_on_user_id_and_employee_code", unique: true
    t.index ["user_id"], name: "index_employees_on_user_id"
  end

  create_table "exam_batch_panelists", force: :cascade do |t|
    t.bigint "exam_batch_id", null: false
    t.bigint "employee_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_exam_batch_panelists_on_employee_id"
    t.index ["exam_batch_id", "employee_id"], name: "index_exam_batch_panelists_on_exam_batch_id_and_employee_id", unique: true
    t.index ["exam_batch_id"], name: "index_exam_batch_panelists_on_exam_batch_id"
  end

  create_table "exam_batches", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "quiz_id", null: false
    t.bigint "vacancy_id"
    t.string "name", null: false
    t.datetime "interview_date"
    t.string "interview_mode"
    t.string "location"
    t.text "notes"
    t.integer "max_warnings", default: 5, null: false
    t.datetime "link_expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "vacancy_title"
    t.string "department"
    t.string "watch_token"
    t.string "meeting_link"
    t.string "interview_plan", default: "separate", null: false
    t.string "language", default: "en", null: false
    t.index ["quiz_id"], name: "index_exam_batches_on_quiz_id"
    t.index ["user_id"], name: "index_exam_batches_on_user_id"
    t.index ["vacancy_id"], name: "index_exam_batches_on_vacancy_id"
    t.index ["watch_token"], name: "index_exam_batches_on_watch_token", unique: true
  end

  create_table "interview_feedbacks", force: :cascade do |t|
    t.bigint "invitation_id", null: false
    t.bigint "employee_id"
    t.bigint "user_id"
    t.string "reviewer_name", null: false
    t.jsonb "scores", default: {}, null: false
    t.string "recommendation", null: false
    t.text "comments"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "interview_round_id"
    t.index ["employee_id"], name: "index_interview_feedbacks_on_employee_id"
    t.index ["interview_round_id", "employee_id"], name: "index_feedbacks_round_employee", unique: true, where: "(employee_id IS NOT NULL)"
    t.index ["interview_round_id", "user_id"], name: "index_feedbacks_round_user", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["interview_round_id"], name: "index_interview_feedbacks_on_interview_round_id"
    t.index ["invitation_id"], name: "index_interview_feedbacks_on_invitation_id"
    t.index ["user_id"], name: "index_interview_feedbacks_on_user_id"
  end

  create_table "interview_round_panelists", force: :cascade do |t|
    t.bigint "interview_round_id", null: false
    t.bigint "employee_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_interview_round_panelists_on_employee_id"
    t.index ["interview_round_id", "employee_id"], name: "index_round_panelists_unique", unique: true
    t.index ["interview_round_id"], name: "index_interview_round_panelists_on_interview_round_id"
  end

  create_table "interview_rounds", force: :cascade do |t|
    t.bigint "invitation_id", null: false
    t.string "name", null: false
    t.integer "position", default: 1, null: false
    t.jsonb "parameters", default: [], null: false
    t.datetime "scheduled_at"
    t.string "meeting_link"
    t.string "status", default: "scheduled", null: false
    t.datetime "started_at"
    t.datetime "ended_at"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invitation_id"], name: "index_interview_rounds_on_invitation_id"
  end

  create_table "invitation_panelists", force: :cascade do |t|
    t.bigint "invitation_id", null: false
    t.bigint "employee_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_invitation_panelists_on_employee_id"
    t.index ["invitation_id", "employee_id"], name: "index_invitation_panelists_on_invitation_id_and_employee_id", unique: true
    t.index ["invitation_id"], name: "index_invitation_panelists_on_invitation_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "quiz_id", null: false
    t.string "candidate_name", null: false
    t.string "candidate_email"
    t.string "candidate_phone"
    t.string "vacancy", null: false
    t.string "department"
    t.string "experience"
    t.datetime "interview_date"
    t.string "interview_mode"
    t.string "location"
    t.text "notes"
    t.string "token", null: false
    t.string "status", default: "pending", null: false
    t.string "entered_phone"
    t.string "otp_code"
    t.datetime "otp_expires_at"
    t.integer "otp_attempts", default: 0, null: false
    t.datetime "verified_at"
    t.datetime "started_at"
    t.datetime "submitted_at"
    t.datetime "link_expires_at"
    t.integer "score"
    t.integer "total_marks"
    t.jsonb "answers", default: {}, null: false
    t.integer "warnings_count", default: 0, null: false
    t.integer "max_warnings", default: 5, null: false
    t.string "termination_reason"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "vacancy_id"
    t.bigint "exam_batch_id"
    t.string "watch_token"
    t.string "interview_status"
    t.datetime "interview_started_at"
    t.string "meeting_link"
    t.string "interview_plan", default: "separate", null: false
    t.string "decision"
    t.text "decision_note"
    t.datetime "decided_at"
    t.text "rough_notes"
    t.string "language", default: "en", null: false
    t.index ["exam_batch_id"], name: "index_invitations_on_exam_batch_id"
    t.index ["quiz_id"], name: "index_invitations_on_quiz_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
    t.index ["user_id"], name: "index_invitations_on_user_id"
    t.index ["vacancy_id"], name: "index_invitations_on_vacancy_id"
    t.index ["watch_token"], name: "index_invitations_on_watch_token", unique: true
  end

  create_table "proctor_events", force: :cascade do |t|
    t.bigint "invitation_id", null: false
    t.string "kind", null: false
    t.string "message"
    t.string "severity", default: "warning", null: false
    t.jsonb "metadata", default: {}, null: false
    t.datetime "acknowledged_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["invitation_id"], name: "index_proctor_events_on_invitation_id"
  end

  create_table "questions", force: :cascade do |t|
    t.bigint "quiz_id", null: false
    t.text "body", null: false
    t.jsonb "options", default: [], null: false
    t.integer "correct_index", default: 0, null: false
    t.integer "marks", default: 1, null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.text "body_hi"
    t.jsonb "options_hi", default: [], null: false
    t.index ["quiz_id"], name: "index_questions_on_quiz_id"
  end

  create_table "quizzes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "duration_minutes", default: 30, null: false
    t.integer "pass_percentage", default: 60, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "show_result_to_candidate", default: false, null: false
    t.index ["user_id"], name: "index_quizzes_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "vacancies", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "department_id", null: false
    t.string "title", null: false
    t.string "code"
    t.date "issue_date"
    t.date "end_date"
    t.integer "positions", default: 1, null: false
    t.text "qualification"
    t.string "experience_required"
    t.jsonb "selection_parameters", default: [], null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["department_id"], name: "index_vacancies_on_department_id"
    t.index ["user_id"], name: "index_vacancies_on_user_id"
  end

  create_table "vacancy_panelists", force: :cascade do |t|
    t.bigint "vacancy_id", null: false
    t.bigint "employee_id", null: false
    t.string "role"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["employee_id"], name: "index_vacancy_panelists_on_employee_id"
    t.index ["vacancy_id", "employee_id"], name: "index_vacancy_panelists_on_vacancy_id_and_employee_id", unique: true
    t.index ["vacancy_id"], name: "index_vacancy_panelists_on_vacancy_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "call_messages", "interview_rounds"
  add_foreign_key "call_messages", "invitations"
  add_foreign_key "code_pads", "interview_rounds"
  add_foreign_key "code_pads", "invitations"
  add_foreign_key "departments", "users"
  add_foreign_key "employees", "users"
  add_foreign_key "exam_batch_panelists", "employees"
  add_foreign_key "exam_batch_panelists", "exam_batches"
  add_foreign_key "exam_batches", "quizzes"
  add_foreign_key "exam_batches", "users"
  add_foreign_key "exam_batches", "vacancies"
  add_foreign_key "interview_feedbacks", "employees"
  add_foreign_key "interview_feedbacks", "interview_rounds"
  add_foreign_key "interview_feedbacks", "invitations"
  add_foreign_key "interview_feedbacks", "users"
  add_foreign_key "interview_round_panelists", "employees"
  add_foreign_key "interview_round_panelists", "interview_rounds"
  add_foreign_key "interview_rounds", "invitations"
  add_foreign_key "invitation_panelists", "employees"
  add_foreign_key "invitation_panelists", "invitations"
  add_foreign_key "invitations", "exam_batches"
  add_foreign_key "invitations", "quizzes"
  add_foreign_key "invitations", "users"
  add_foreign_key "invitations", "vacancies"
  add_foreign_key "proctor_events", "invitations"
  add_foreign_key "questions", "quizzes"
  add_foreign_key "quizzes", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "vacancies", "departments"
  add_foreign_key "vacancies", "users"
  add_foreign_key "vacancy_panelists", "employees"
  add_foreign_key "vacancy_panelists", "vacancies"
end
