module AmazonAPI

  class Start

    def initialize(ary)
      @cmd = ary[0] ||= 'l' 
      @isbn = ary[1]
      @opt = ary[1] ||= '10'
      @word = ary[1]
    end

    def starter
      case @cmd
      when 'add' then AwsDataWriter.new(@isbn).list_update
      when 'l' then AwsDataReader.new().list_view(@opt.to_i-1)
      when 's' then AwsDataReader.new().list_search(@word)
      when 'isbn' then AwsDataReader.new().list_isbn_view
      end
    end

  end 

  class AmazonAccess

    def initialize(ean)
      @ean = ean 
      @aws_uri = URI.parse(jp_url)
    end 

    def base
      set_uri
      xml = access
      data = AwsXML.new(xml, amazon_id).base if xml 
      return data
    end 

  end

  class AwsDataWriter

    def initialize(ean)
      @ean = ean
      @h = load_list
      @dpath = File.join(data_path, 'db-data')
    end

    # new item add to the list.
    def list_update
      return nil unless ean_ok?
      set_item
      item_add
      save_text if @item
    end

    def item_delete
      check = @h.delete(@ean)
      save_list unless check.nil?
    end

    private
    def ean_ok?
      return false if @ean.size < 9 or @ean.size > 13
      return false if m = /\D/.match(@ean)
      return true
    end

    # @item object is based on amazon data hash.
    def set_item
      item_h = AmazonAccess.new(@ean).base
      return nil unless item_h
      item_h[:created] = Time.now.to_s # for import data
      @item = AwsItem.new(item_h)
      @item_h = item_h if @item
    end

    def item_add
      return nil unless @item
      return nil unless @item_h
      @h[@item.ean] = @item_h
      save_list
    end

    def save_list
      m_writer(@dpath, @h)
      print "Saved: #{@dpath}\n"
    end

    def save_text
      return nil if FileTest.exist?(text_path)
      writer(text_path, @item.to_s_txt)
      print "Saved: #{@item.title}\n"
    end

    def text_path
      File.join(data_path, 'text', @item.ean + ".txt")
    end

  end

  class AwsDataReader

    def initialize
      @ary = Array.new
      load_base
    end

    # print list
    def list_view(num)
      @ary.each_with_index{|i,n| break if n > num; print (n+1); i.to_s}
      choose_option
    end

    # print all isbn
    def list_isbn_view
      @ary.each{|x| print x.ean, "\n"}
    end

    # search keyword in title or artist, author, lavel, publisher...  
    def list_search(w)
      a = []
      @ary.each{|i| a << i if i.detail.downcase.include?(w.downcase)}
      return nil if a.empty?
      @ary = a
      @ary.each{|x| x.to_s}
      choose_option
    end

    private
    def load_base
      load_list.each{|k,v| @ary << AwsItem.new(v)}
      @ary = @ary.sort_by{|i| i.created.to_s}.reverse[0..10]
    end

    def choose_option
      item = choose_item
      act = choose_act if item
      item_act(act, item) if act and item
    end

    def choose_item
      return @ary[0] if @ary.size == 1
      n = selector("Select No", @ary.size)
      return @ary[n.to_i-1] if n
    end

    def choose_act
      act = selector("Select [i/e/r/n]", false)
      return act if act
    end

    def item_act(act, item)
      instance_variables.each{|i| instance_variable_set(i, nil)}
      case act
      when 'i' then item_detail(item)
      when 'e' then item_open(item)
      when 'r' then item_remove(item)
      else return nil 
      end
    end

    def selector(str, opt)
      ans = BaseMessage.message(str, opt)
      return ans 
    end

    def item_remove(item)
       AwsDataWriter.new(item.ean).item_delete
    end

    def item_detail(item)
      print item.detail
    end

    def item_open(item)
      instance_variables.each{|i| instance_variable_set(i,nil)}
      f = File.join(data_path, 'text', item.ean + ".txt")
      return nil unless File.exist?(f)
      exec("vim #{f}")
    end

  end

  class AwsItem

    def initialize(h)
      set_up(h) if h
      @created ||= Time.now.to_s
    end

    attr_reader :ean, :created, :title

    def to_s
      ary = []
      # memo  @created is saved as {:created=>"2010-04-20 20:16:35 +0900"} in Marshal data
      @created = Time.parse(@created.to_s).strftime("%Y/%m/%d")
      to_a.each{|x| ary << self[x.to_s]}
      printf "\t[%-13s][%-5s][%s] %s\s|\s%s\s|\s%s\n" % ary
    end

    def to_s_txt
      str = String.new("").encode("UTF-8")
      to_a.each{|x| str << x.to_s.gsub("@","--") + "\n" + self[x] + "\n"}
      return str
    end

    def detail
      str = ""
      ins_a.each{|i| str << i.to_s.gsub("@",'').upcase + ":\s" + self[i] + "\n" }
      return str
    end

    private
    def to_a
      x = [:@ean, :@productgroup, :@created, :@title, :@author, :@publicationdate]
      y = [:@ean, :@productgroup, :@created, :@title, :@artist, :@releasedate]
      @producttypename.downcase =~ /book/ ? x : y
    end

    def set_up(h)
      h.each{|k,v| self["@#{k.downcase}"] = v}
    end

    alias []= instance_variable_set
    alias [] instance_variable_get
    alias ins_a instance_variables

  end

  class AwsXML
    # reference: http://yugui.jp/articles/850
    # about xml.force_encoding("UTF-8")
    def initialize(xml, aws_id=nil)
      if xml
        (xml.include?("Error")) ? (print "ErrorXML \n") : @xml = REXML::Document.new(xml)
      end
      @h = Hash.new
      @aws_id = aws_id
    end

    def base
      return nil unless @xml
      getelement
      set_data
      return @h
    end

    private
    def getelement
      ei = @xml.root.elements["Items/Item"]
      @attrib = get(ei, "ItemAttributes")
      @img = get(ei, "MediumImage")
      @url = get(ei, "DetailPageURL")
      @rank = get(ei, "SalesRank").text
    end

    def set_data
      @attrib.each{|x| @h[x.name] = plural(@attrib, x.name)}
      @h.delete_if{|k,v| v.nil?}
      @h["MediumImage"] = @img.elements["URL"].text unless @img.nil?
      @h["Price"] = @attrib.elements["ListPrice/FormattedPrice"].text.gsub(/\D/,'')
      @h["Rank"] = @rank
      @h["DetailPageURL"] = seturl
    end

    def get(ele, str)
      ele.elements[str]
    end

    def plural(ele, str)
      e = ele.get_elements(str)
      case e.size
      when 0
      when 1 then ele.elements[str].text
      else
        @h[str] = e.map{|i| i.text}.join(" / ")
      end
    end

    def seturl
      url = exurl(@url.text)
      return nil unless url
      eurl = url.gsub(/\?SubscriptionId=.*/,'')
      m = /amazon.co.jp\/(.*?\/)/.match(eurl)
      v = eurl.gsub(m[1], '')
      v << "?tag=#{@aws_id}" if @aws_id
      return v
    end

    def exurl(string)
      str = string.gsub(/%([0-9a-fA-F]{2})/){[$1.delete('%')].pack("H*")}
      return str if str.valid_encoding?
    end

  end

  module Reader

    include $MYDATACONF 
    def m_reader(path)
      f = open(path, "r")
      data = Marshal.load(f)
      f.close
      return data
    end

    def load_list
      path = File.join(data_path, 'db-data')
      raise "Error: load_data_error\n" unless path 
      list = m_reader(path)
      raise "Error: load_data_error\n" unless list
      raise "Error: data EMPTY\n" if list.empty?
      return list
    end

  end

  module Writer

    def writer(path, data)
      File.open(path, 'w:utf-8'){|f| f.print data}
    end

    def m_writer(path, data)
      f = open(path, "w")
      Marshal.dump(data, f)
      f.close
    end

  end

  module ReaderWriter
    include Reader
    include Writer
  end

  module BaseMessage

    def self.message(str, opt)
      sec, ans = 5, ''
      begin
        timeout(sec){ans = interactive(str, opt)}
      rescue TimeoutError
        return print "Timeout. #{sec} sec.\n"
      rescue RuntimeError
        return print "Timeout. #{sec} sec.\n"
      rescue SignalException
        return print "\n"
      end
      return ans #unless ans.empty?
    end

    def self.interactive(msg, opt)
      return false unless $stdin.tty?
      print "#{msg}:\n"
      ans = $stdin.gets.chomp
      return false if /^n$|^no$/.match(ans) # n or no == stop
      return false if ans.empty?
      case opt
      when true   # yes or no
        m = /^y$|^yes$/.match(ans)
        return false unless m
        return true
      when false  # return alphabet
        return false if /\d/.match(ans)
        return false if ans.size > 7
        return ans
      else        # return number
        i_ans = ans.to_i
        return false if i_ans > opt
        return false if ans =~ /\D/
        return false unless ans
        return ans.to_i
      end
    end

  end

  module AmazonAuth 

    private
    def set_uri
      @aws_uri.path = '/onca/xml'
      req = set_query.flatten.sort.join("&")
      msg = ["GET", @aws_uri.host, @aws_uri.path, req].join("\n")
      hash = OpenSSL::HMAC::digest(OpenSSL::Digest::SHA256.new, amazon_sec, msg)
      mh = [hash].pack("m").chomp
      sig = escape(mh)
      @aws_uri.query = "#{req}&Signature=#{sig}"
      return @aws_uri
    end

    def access
      host = @aws_uri.host
      request = @aws_uri.request_uri
      doc = nil
      begin
        Net::HTTP.start(host){|http|
          response = http.get(request)
          doc = response.body
        }
      rescue SocketError
        return print "SocketError \n"
      end
      v = doc.valid_encoding?
      return print "Not ValidXML\n" unless v
      return doc
    end

    def set_type(q)
      case @ean.size
      when 10 then q << ["SearchIndex=Books" ,"IdType=ISBN"]
      when 12 then q << ["SearchIndex=Music", "IdType=EAN"]
      when 13
        if m = /^978|^491/.match(@ean)
          q << ["SearchIndex=Books" ,"IdType=ISBN"]
        elsif m = /^458/.match(@ean)
          q << ["SearchIndex=DVD", "IdType=EAN"]
        else
          q << ["SearchIndex=Music", "IdType=EAN"]
        end
      end
      return q
    end

    def set_query
      q = [
        "Service=AWSECommerceService",
        "AWSAccessKeyId=#{amazon_key}",
        "Operation=ItemLookup",
        "ItemId=#{@ean}",
        "ResponseGroup=Medium",
        "Timestamp=#{local_utc}",
        "Version=2009-03-31"
      ]
      return set_type(q)
    end

    def escape(str)
      str.gsub(/([^ a-zA-Z0-9_.-]+)/){'%' + $1.unpack('H2' * $1.bytesize).join('%').upcase}.tr(' ', '+')
    end

    def local_utc
      escape(Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ'))
    end

  end

  AwsDataReader.send :include, Reader
  AwsDataWriter.send :include, ReaderWriter
  AmazonAccess.send :include, $MYAMAZON
  AmazonAccess.send :include, AmazonAuth

end

