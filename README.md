###Description:
Processing of files, particularly large images can lead
to delays in user interaction with a web site.
CarrierWaveDirect is a gem that allows for the
processing and saving of files in a background process
allowing users to have a more seamless transition
between pages.

This tutorial takes the approach of stepping through the process of image
uploading beginning with CarrierWave to illustrate the basics, followed by using
AWS S3 with CarrierWave-Direct, Redis, and Sidekiq.  This tutorial also took the
approach of commit early/commit often so if in doubt refer to the history.

###Gotchas:

In the short duration of making this tutorial a number of issues have popped up
during the iterations.  To save some headaches, the following is worth keeping
in mind in case there is quirky behavior or errors occurring.

* Spring stop.  It has been noted that spring has a
tendency to cause hang ups.

* When in doubt, check logs and reset the server.

* In case there is an issue with: NameError: unitialized constant User::AvatarUploader

  add require 'carrierwave/orm/activerecord' to config/environment.rb

* In case:  The version of OpenSSL this ruby is built against (1.0.2) has a vulnerability which causes a fault.

  Simple solution: Downgrade Openssl

**Prerequisites:**

Setting up an AWS image bucket is beyond the scope
of this tutorial.  Visit: <http://docs.aws.amazon.com/AmazonS3/latest/gsg/GetStartedWithS3.html> for further information.

In addition ImageMagick must be installed.

**Resources:**

This tutorial is influenced and has liberally referenced Ryan Bates RailsCast:

<http://railscasts.com/episodes/253-carrierwave-file-uploads>

<http://railscasts.com/episodes/383-uploading-to-amazon-s3>

Gem Resources:

Fog: <http://fog.io/storage/>
Figaro: <https://github.com/laserlemon/figaro>


Sidekiq: <http://sidekiq.org>

CarrierWaveDirect: <https://github.com/dwilkie/carrierwave_direct>

CarrierWave <https://github.com/carrierwaveuploader/carrierwave>

###Gems

* carrierwave
* carrierwave_direct
* figaro
* sidekiq
* rmagick
* fog


#Carrier Wave

Beginning the project:

    rails new <project name>
    gem carrierwave
    bundle
    rails g scaffold user name --no-test-framework
    rake db:migrate
    rails g uploader avatar
    rails g migration add_avatar_to_users avatar
    rake db:migrate

At this point the working foundation of the project is in place and carrier wave
can now be built.

* Modify app/models/users.rb
* ` mount_uploader :avatar, AvatarUploader `
* Alter first line and add file_field to app/views/ _form.html.erb

```
<%= form_for(@user, :html => { :multipart => true }) do |f| %>

<div class="div">
  <%= f.file_filed :avatar %>
</div>
```
* Modify app/views/show.html.erb

```
<p>
  <strong>Avatar:</strong>
  <%= image_tag user.avatar_url.to_s %>
</p>
```

* Modify users__controller strong`_`params to account for :avatar

* Resize the image

` gem 'imagemagick' `

` bundle `

* Modify avatar_uploader
  * Uncomment ` include CarrierWave::RMagick `
  * Uncomment code block: ` version :thumb do
  * Modify ` process :resize_to_fit => [50, 50] ` to desired size
  * Replace ` <%= image_tag user.avatar_url.to_s %> ` with ` <%= image_tag user.avatar_url(:thumb).to_s %> `

##### Voila:
At this stage CarrierWave is functioning and CarrierWaveDirect can now be
configured.  This will be broken down into steps, the first being to get S3
 working.  This step involves using AWS keys so in order to protect them from
 accidental placement on GitHub, Figaro will be used to store them.
 The benefit of Figaro is that it will place a line in .gitignore file,
 but it's always important to double check and verify it has done so.
 In addition add the included gems.

#CarrierWave-Direct

    gem 'carrierwave_direct'
    gem 'fog'
    gem 'sidekiq'
    gem 'figaro'

After bundling run ` figaro install ` to install the application.yml.
Verify .gitignore includes:

    # Ignore application configuration
    /config/application.yml


* Add S3 keys to application.yml

```
AWS_S3_Bucket: your bucket
AWS_ACCESS_KEY_I: your key
AWS_SECRET_ACCESS_KEY: your key
```

* Create config/initializes/carrierwave.rb file
* Add the following

```
CarrierWave.configure do |config|
  config.fog_credentials = {
    provider: "AWS",
    aws_access_key_id: ENV["AWS_ACCESS_KEY_ID"],
    aws_secret_access_key: ENV["AWS_SECRET_ACCESS_KEY"],
    :region  => 'us-west-2'
  }
  config.fog_directory = ENV["AWS_S3_BUCKET"]
end
```
CarrierWave is now configured to upload files to a S3 bucket and returned in an
avatar sized image.  There is a delay however, and this is the cost of placing
flow of control in the hands of a 3rd party.  The app is now dependent upon the
processing time outside of the programs flow of control which can lead to
unintended consequences and effect the user experience.  To alleviate this,
using Sidekiq to process in the background is greatly complimentary with
CarrierWave-Direct which the following steps configure.

* In avatar_uploader add ` include CarrierWaveDirect::Uploader `
* CW-D defaults to :fog for storge so this can be taken out.
* Add the following to this file:

```
include CarrierWave::MimeTypes
process :set_content_type
```

* Remove ` def store_dir ` method as S3 will now be responsible

With this in place it is now time to modify the form so that image uploading is
 a distinct sequence from inputting of a users name.  To do this in a simple
 scaffolded project add ` root "users#index ` to routes.rb.  The index page will
 be modified to have a field for the uploading of an image before rendering the
 new user form while the image processes in the background.

In the index file remove the link to 'New User' and replace it with the following:

```
<%= direct_upload_form_for @uploader do |f| %>
  <p><%= f.file_field :avatar %> </p>
  <p><%= f.submit "Upload Avatar" %></p>
<% end %>
```

* In users_controller.rb modify ` def index ` to include the following:

```
@users = User.all
@uploader = User.new.avatar
@uploader.success_action_redirect = new_user_url
```

S3 returns a key that will be used in the User#new to keep track of the image
during this cycle, so add the following to _form, then make appropriate changes
to strong params:

 ``` <%= f.hidden_field :key %> ```


 All the pieces are now in place to be able to test at this stage whether or not
 images are being processed by S3.  If all is functioning as expected, the next
 step is to have a worker do this processing in the background.

 It is useful to add a migration to determine whether or not an image has been
 processed yet or not.

 ```
 rails g migration add_avatar_processed_to_users avatar_processed_boolean
 rake migrate:db
 ```
 Next modify models/user.rb to include the following:

```
  after_save :enqueue_avatar

  def enqueue_avatar
    AvatarWorker.perform_async(id, key) if key.present?
  end

  class AvatarWorker
    include Sidekiq::Worker

    def perform(id, key)
      user = User.find(id)
      user.key = key
      user.remote_avatar_url = user.avatar.direct_fog_url(with_path: true)
      user.save!
      user.update_column(:avatar_processed, true)
    end
  end
```


This sets up the worker that will be used by Sidekiq to do the processing as
the user transitions from uploding an image to be resized into an avatar to
filling out the user name.  Now it's time for testing.  For this Redis should be
 installed and started, as well as Sidekiq and the rails server.
