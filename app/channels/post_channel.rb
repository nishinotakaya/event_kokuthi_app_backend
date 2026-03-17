class PostChannel < ApplicationCable::Channel
  def subscribed
    stream_from "post_#{params[:job_id]}"
  end

  def unsubscribed
    stop_all_streams
  end
end
