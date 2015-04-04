# encoding: utf-8

class AvatarUploader < CarrierWave::Uploader::Base
  include CarrierWaveDirect::Uploader
  # Include RMagick or MiniMagick support:
  include CarrierWave::RMagick
  include CarrierWave::MimeTypes
  process :set_content_type

  # include CarrierWave::MiniMagick

  # Choose what kind of storage to use for this uploader:
  # storage :file
  storage :fog

  # Create different versions of your uploaded files:
  version :thumb do
    process :resize_to_fit => [100, 100]
  end
end
