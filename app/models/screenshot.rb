require 'open-uri'
require 'mini_magick'

# Class to cache and resize the screenshot of a given package
class Screenshot
  THUMBNAIL_WIDTH = "600"

  # @return [String] name of the package
  attr_reader :pkg_name
  # @return [String] original (remote) location of the screenshot
  attr_reader :source_url

  def initialize(pkg_name, source_url = nil)
    @pkg_name = pkg_name
    @source_url = source_url
  end

  # Relative path of the thumbnail, ready to be passed to #image_tag
  #
  # If the thumbnail is already available locally or is one of the default
  # images (i.e. there is no remote screenshot), it will return the correct
  # path right away.
  #
  # If the screenshot is available remotely but the thumbnail is still not
  # generated, it will generate the thumbnail before returning the url if
  # :fetch is true or will return nil if :fetch is false.
  #
  # @return [String]
  def thumbnail_path(fetch: true)
    if cached?
      thumbnail_file_path(fullpath: false)
    elsif source_url.nil?
      default_file_path(fullpath: false)
    elsif fetch
      begin
        self.fetch
        thumbnail_file_path(fullpath: false)

      # This is sensitive enough (depending on an external system) to
      # justify an agressive rescue. #open can produce the following
      # rescue Errno::ETIMEDOUT, Net::ReadTimeout, OpenURI::HTTPError => e
      # And also there is a chance of exception generating the thumbnail
      rescue Exception => e
        raise unless Rails.env.production?
        Rails.logger.debug("No screenshot fetched for: " + pkg_name)
        default_file_path(fullpath: false)
      end
    else
      nil
    end
  end

  # Image content ready to be served.
  #
  # If the content is already available locally, it will be served from the
  # cache. Otherwise, it will be downloaded and processed first.
  #
  # @param type [Symbol] :thumbnail or :screenshot
  def blob(type = :screenshot)
    if cached?
      cached_blob(type)
    elsif source_url.nil?
      default_blob
    else
      begin
        fetch
        cached_blob(type)

      # This is sensitive enough (depending on an external system) to
      # justify an agressive rescue. #open can produce the following
      # rescue Errno::ETIMEDOUT, Net::ReadTimeout, OpenURI::HTTPError => e
      # And also there is a chance of exception generating the thumbnail
      rescue Exception => e
        raise unless Rails.env.production?
        Rails.logger.debug("No screenshot fetched (blob) for: " + pkg_name)
        default_blob
      end
    end
  end

protected

  def cached?
    Rails.cache.exist? cache_key
  end

  def cached_blob(type)
    if type == :thumbnail
      open(thumbnail_file_path, "rb", &:read)
    else
      Rails.cache.read(cache_key)
    end
  end

  def default_blob
    open(default_file_path, "rb", &:read)
  end

  def cache_key
    "t:screenshot-p:#{pkg_name}"
  end

  def generate_thumbnail(content)
    img = MiniMagick::Image.read(content)
    img.resize THUMBNAIL_WIDTH
    img.write thumbnail_file_path
  end

  def fetch
    Rails.logger.debug("Fetching screenshot from #{source_url}")
    begin
      content = open(source_url, "rb", :read_timeout => 6)
    rescue Exception => e
      # redirects will fail https://bugs.ruby-lang.org/issues/859 so try to follow
      url_regex = /https?:\/\/[\S]+/
      redirect_url = e.to_s.scan(url_regex).last
      content = open(redirect_url, "rb", :read_timeout => 6)
    end
    generate_thumbnail(content)
    Rails.cache.write(cache_key, content.read)
  ensure
    content.close if content && !content.closed?
  end

  def thumbnail_file_path(fullpath: true)
    file = "thumbnails/#{pkg_name}.png"
    fullpath ? File.join(Rails.root, "public", "images", file) : file
  end

  def default_file_path(fullpath: true)
    file = case pkg_name
    when /-devel$/
      "devel-package.png"
    when /-devel-/
      "devel-package.png"
    when /-debug$/
      "devel-package.png"
    when /-lang$/
      "lang-package.png"
    when /-l10n-/
      "lang-package.png"
    when /-i18n-/
      "lang-package.png"
    when /-translations/
      "lang-package.png"
    when /-doc$/
      "doc-package.png"
    when /-help-/
      "doc-package.png"
    when /-javadoc$/
      "doc-package.png"
    when /-debuginfo/
      "devel-package.png"
    when /-debugsource/
      "devel-package.png"
    when /-kmp-/
      "devel-package.png"
    when /^rubygem-/
      "ruby-package.png"
    when /^perl-/
      "perl-package.png"
    when /^python-/
      "python-package.png"
    when /^python2-/
      "python-package.png"
    when /^python3-/
      "python-package.png"
    when /^kernel-/
      "kernel-package.png"
    when /^openstack-/i
      "openstack-package.png"
    else
      "package.png"
    end
    if fullpath
      File.join(Rails.root, "app/assets/images/default-screenshots", file)
    else
      "default-screenshots/#{file}"
    end
  end
end
