

module WWW
  class Mechanize
    def post_with_headers(url, query={}, headers={})
      node = {}
      # Create a fake form
      class << node
        def search(*args); []; end
      end
      node['method'] = 'POST'
      node['enctype'] = 'application/x-www-form-urlencoded'

      form = Form.new(node)
      query.each { |k,v|
        if v.is_a?(IO)
          form.enctype = 'multipart/form-data'
          ul = Form::FileUpload.new(k.to_s,::File.basename(v.path))
          ul.file_data = v.read
          form.file_uploads << ul
        else
          form.fields << Form::Field.new(k.to_s,v)
        end
      }
      post_form(url, form)
    end
  end
end