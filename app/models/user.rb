class User < ActiveRecord::Base
  mount_uploader :avatar, AvatarUploader

  after_save :enqueue_avatar

  def enqueue_avatar
    AvatarWorker.perform_async(id, key) if key.present?
  end

  class AvatarWorker
    include Sidekiq::Worker

    def perform(id, key)
      avatar = User.find(id)
      user.key = key
      user.remote_avatar_url = user.avatar.direct_fog_url(with_path: true)
      user.save!
      user.update_column(:avatar_processed, true)
    end
  end
end
