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

ActiveRecord::Schema[8.1].define(version: 2026_04_18_202316) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "agents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.jsonb "context_files", default: [], null: false
    t.datetime "created_at", null: false
    t.text "descripcion"
    t.string "nombre", limit: 200, null: false
    t.text "steering_document", default: "", null: false
    t.datetime "updated_at", null: false
  end

  create_table "workflow_definitions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "default_agent_id"
    t.text "descripcion"
    t.jsonb "drawflow_data", default: {}, null: false
    t.boolean "is_active", default: true, null: false
    t.string "nombre", limit: 200, null: false
    t.datetime "updated_at", null: false
  end

  create_table "workflow_runs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.text "input_text"
    t.jsonb "node_states", default: {}, null: false
    t.string "run_dir"
    t.datetime "started_at"
    t.string "status", limit: 20, default: "pending", null: false
    t.datetime "updated_at", null: false
    t.uuid "workflow_definition_id", null: false
    t.index ["workflow_definition_id"], name: "index_workflow_runs_on_workflow_definition_id"
  end

  add_foreign_key "workflow_runs", "workflow_definitions"
end
