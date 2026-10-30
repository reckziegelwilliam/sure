require "test_helper"

class TellerConnectionUpdateJobTest < ActiveJob::TestCase
  test "enqueues on the default queue" do
    item = teller_items(:chase_connection)
    assert_enqueued_with(job: TellerConnectionUpdateJob) do
      TellerConnectionUpdateJob.perform_later(item)
    end
  end

  test "perform calls Importer#import" do
    item = teller_items(:chase_connection)
    TellerItem::Importer.any_instance.expects(:import).once

    TellerConnectionUpdateJob.perform_now(item)
  end
end
