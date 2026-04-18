class WorkflowDefinition < ApplicationRecord
  has_many :workflow_runs, dependent: :destroy

  validates :nombre, presence: true, length: { maximum: 200 }
  validates :drawflow_data, presence: true

  def last_run = workflow_runs.order(created_at: :desc).first
end
