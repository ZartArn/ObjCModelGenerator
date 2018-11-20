require 'json'
require 'date'
require 'erubis'

def check_date_str(date_str)
  DateTime.iso8601(date_str)
  return true
rescue ArgumentError
  false
  # although, in my case I felt that logging this error and raising exception was a better approach, since we are forwarding this to the user of our API.
  # log_and_raise_error("Given argument is not a valid ISO8601 date: '#{date}'")
end

class MProperty
  attr_accessor :class_type, :property, :key_path
end


class ModelProperty
  attr_accessor :name, :key_path, :value
end

class AbstractModel

  attr_accessor :class_name, :property, :key_path, :single_properties, :has_one_properties, :has_many_properties

  def initialize
    @single_properties = []
    @has_one_properties = []
    @has_many_properties = []
  end

end

class Templator
  
  # render AbstarctModel model
  def render(model, template_name)
    source = File.read(template_name)
    eruby = Erubis::Eruby.new source
    eruby.result(:model => model)
  end

end

class ModelGenerator

  attr_accessor :root_class_name, :class_prefix, :root_object

  def initialize (root_class_name, class_prefix)
    @root_class_name = root_class_name
    @class_prefix = class_prefix
  end


  #import form json file
  def import(filename)
    s = File.open(filename, "r") { |f| f.read }
    return JSON.parse s
  end

  # parse
  def parse(json_hash, parent)
    json_hash.each_pair do |key, value|
      if value.is_a? Array
        inner_json = value.first
        if inner_json.is_a? Hash
          object = AbstractModel.new
          object.class_name = "#{@class_prefix}#{key}"
          object.property = key[0].downcase + key[1..-1]
          object.key_path = key
          parent.has_many_properties << parse(inner_json, object)
        else
          property = ModelProperty.new
          property.name = key[0].downcase + key[1..-1]
          property.key_path = key
          property.value = [inner_json]
          parent.single_properties << property
        end
      elsif value.is_a? Hash
        object = AbstractModel.new
        object.class_name = "#{@class_prefix}#{key}"
        object.property = key[0].downcase + key[1..-1]
        object.key_path = key
        parent.has_one_properties << parse(value, object)
      else
        property = ModelProperty.new
        property.name = key[0].downcase + key[1..-1]
        property.key_path = key
        property.value = value
        parent.single_properties << property
      end
    end
    parent
  end

  # find child classes
  def collect_classes(m, arr)
    m.has_one_properties.each do |m0|
      arr << collect_classes(m0, arr)
    end
    m.has_many_properties.each do |m0|
      arr << collect_classes(m0, arr)
    end
    m
  end

  # find all classes
  def collect_models
    models = []
    models << collect_classes(@root_object, models)
    models
  end

  #generate final objects
  def objc_models(models)
    fail 'models must be Array' unless models.is_a? Array

    models.map do |item|

      m = AbstractModel.new
      m.class_name = item.class_name
      m.property = item.property
      m.key_path = item.key_path

      item.single_properties.map do |property|
        p = MProperty.new
        p.property = property.name
        p.key_path = property.key_path
        val = property.value
        p.class_type = 'NSNumber' if (val.is_a? Integer) || (val.is_a? Float) || ([true, false].include? val)
        p.class_type ||= 'NSArray' if val.is_a? Array
        if (val.is_a? String) && ((property.name.include? 'Date') || (property.name.include? 'Day'))
          #try parse date
          p.class_type = 'NSDate' if check_date_str val
        end
        p.class_type ||= 'NSString' #if val.is_a? String
        m.single_properties << p
      end

      item.has_one_properties.map do |property|
        p = MProperty.new
        p.property = property.property
        p.key_path = property.key_path
        p.class_type = property.class_name
        m.has_one_properties << p
      end

      item.has_many_properties.map do |property|
        p = MProperty.new
        p.property = property.property
        p.key_path = property.key_path
        p.class_type = property.class_name
        m.has_many_properties << p
      end
      m
    end
  end


  #generator
  def generator(json_hash)

    @root_object = AbstractModel.new
    @root_object.class_name = @root_class_name

    parse(json_hash, @root_object)
    models = collect_models
    z = objc_models models

  end

  #render outputs
  def render(models)
    models = models.group_by{|i| i.class_name}

    models.each_pair do |class_name, arr|
      puts "#{class_name} :: #{arr.size}" if arr.size > 1
      templator = Templator.new
      s = templator.render arr.first, 'model.h.erb'
      save "output/#{class_name}.h" , s
      s = templator.render arr.first, 'model.m.erb'
      save "output/#{class_name}.m" , s
    end
  end

  #save to file
  def save(filename, source)
    File.open(filename, "w") { |f| f.write source }
  end

end
