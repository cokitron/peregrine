class WorkflowRun < ApplicationRecord
  belongs_to :workflow_definition

  validates :status, inclusion: { in: %w[pending running completed failed cancelled] }

  scope :recientes, -> { order(created_at: :desc) }

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end
end
