# -*- coding: utf-8 -*-

require 'viddl-rb'
require 'rmagick'
require 'aws-sdk'

class TerminalAa

  def initialize dynamo_db
    @video_url = "http://www.youtube.com/watch?v=oz-7wJJ9HZ0"
    @video_id = URI.decode_www_form(URI.parse(@video_url).query).assoc('v').last.to_s
    @video_dir = File.dirname(File.expand_path(__FILE__)) + "/video/"
    @image_dir = File.dirname(File.expand_path(__FILE__)) + "/image/"

    @table = dynamo_db.tables['youtube_aa']
    @table.hash_key  = [:id, :string]
    @table.range_key = [:no, :number]
  end

  def save
    video_name = download
    if false == image?(video_name)
      puts "exit"
      exit
    end
  end

  def read
    datas = @table.items.query(:hash_value => @video_id, :scan_index_forward => true)
    datas.each do |data|
      puts data.attributes["text"]
    end
  end

  private
  def download
    download_urls = ViddlRb.get_urls_names(@video_url).first
    ViddlRb::DownloadHelper.save_file download_urls[:url], download_urls[:name], :save_dir => @video_dir
    download_urls[:name]
  rescue ViddlRb::DownloadError => e
    puts "Could not get download url: #{e.message}"
    exit
  rescue ViddlRb::PluginError => e
    puts "Plugin blew up! #{e.message}\n" +
      "Backtrace:\n#{e.backtrace.join("\n")}"
    exit
  end

  def image? video_name
    video_path = @video_dir + video_name
    IO.popen("ffmpeg -ss 1 -i '#{video_path}' -vframes 100 -f image2 -r 5 #{@image_dir}%d.jpg") do |io|
      result = io.gets
    end
    File.unlink video_path

    for i in 1..100
      image = Magick::Image.read("#{@image_dir}#{i}.jpg").first
      image.resize_to_fit!(200, 200)
      image.write("#{@image_dir}#{i}.jpg")
      string = `jpegtopnm #{@image_dir}#{i}.jpg | ppmtopgm | pgmtopbm -dither8 | pbmtoascii -1x2`
      @table.items.create({:id => @video_id, :no => i.to_i, :text => string.to_s})
      File.unlink "#{@image_dir}#{i}.jpg"
    end
    true
  rescue
    puts 'Error'
    false
  end

end

AWS.config(
           :access_key_id => ENV["AWS_ACCESS"],
           :secret_access_key => ENV["AWS_SECRET"],
           :dynamo_db_endpoint => 'dynamodb.ap-northeast-1.amazonaws.com'
           )

youtube_aa = TerminalAa.new (AWS::DynamoDB.new)

if ARGV[0] == "save"
  youtube_aa.save
elsif ARGV[0] == "read"
  youtube_aa.read
end
