require_relative 'district_repository'
require_relative 'exceptions'
require_relative 'clean'
require_relative 'district_repository'

class HeadcountAnalyst
  include Clean
  attr_reader :district_repository, :calculate,
              :kindergarten_participation_against_high_school_graduation

  def initialize(dr)
    @district_repository = dr
  end

  def top_statewide_error(data)
    raise InsufficientInformationError,
      "A grade must be provided to answer this question" if data[:grade] == nil
    raise UnknownDataError,
      "#{data[:grade]} is not a known grade" unless
        data[:grade] == 3 || data[:grade] == 8
  end

  def top_statewide_test_year_over_year_growth(data)
    top_statewide_error(data)
    top_statewide_data_control(data)
  end

  def top_statewide_data_control(data)
    options = data.keys.sort
    case options
    when [:grade, :subject]
      simple_top(data)
    when [:grade, :subject, :top]
      n_tops(data)
    when [:grade]
      all_subjects(data, {math: 0.333, reading: 0.333, writing: 0.333})
    when [:grade, :weighting]
      all_subjects(data, data[:weighting])
    end
  end

  def all_subjects(data, weighting)
    results = get_subject_results(data)
    subjects = make_subject_hashes(results[0], results[1], results[2])
    master = load_subject_to_master(subjects[0], subjects[1], subjects[2])
    clean_master = clean_master(master)
    crunch_master(clean_master, weighting)
  end

  def crunch_master(clean_master, weighting)
    clean_master.each do |name, values|
      clean_master[name] = apply_weight(values, weighting)
    end
    master_sum(clean_master)
  end

  def master_sum(clean_master)
    clean_master.each do |name, values|
      clean_master[name] = values.reduce {|sum, value| sum += value}
    end
    polished = clean_and_return(clean_master.to_a)
    polished.last
  end

  def apply_weight(values, weighting)
    result = values.map.with_index do |value, index|
      values[index] = value * weighting.values[index]
    end
    result
  end

  def clean_master(master)
    master.each do |name, growths|
      master[name] = clean_nils(growths)
    end
  end

  def clean_nils(set)
    set = set.map do |value|
      if value == nil
        0
      else
        value
      end
    end
    set
  end

  def make_subject_hashes(math_data, reading_data, writing_data)
    math = Hash[grade_picker(math_data)]
    reading = Hash[grade_picker(reading_data)]
    writing = Hash[grade_picker(writing_data)]
    [math, reading, writing]
  end

  def get_subject_results(data)
    math_data = {:grade => data[:grade], :subject => :math}
    reading_data = {:grade => data[:grade], :subject => :reading}
    writing_data = {:grade => data[:grade], :subject => :writing}
    [math_data, reading_data, writing_data]
  end

  def load_subject_to_master(math, reading, writing)
    master_hash = master_hash_maker
    master_hash.each do |name, values|
      master_hash[name] = [math[name], reading[name], writing[name]]
    end
    master_hash
  end

  def master_hash_maker
    master_hash = {}
    @district_repository.districts.keys.each do |name|
      master_hash[name] = []
    end
    master_hash
  end

  def n_tops(data)
    result = grade_picker(data)
    n_top = []
    data[:top].times {n_top << result.pop}
    return n_top
  end

  def grade_picker(data)
    if data[:grade] == 3
      result = top_statewide(data[:subject], "third_grade")
    else
      result = top_statewide(data[:subject], "eighth_grade")
    end
    clean_and_return(result)
  end

  def simple_top(data)
    result = grade_picker(data)
    result.last
  end

  def top_statewide(subject, grade)
    result = @district_repository.districts.values.map do |district|
      name = district.name
      district = district.statewide_test.send(grade)
      max_year = validate_max_year(district.keys.max, subject, name, grade)
      min_year = validate_min_year(district.keys.min, subject, name, grade)
      next if max_year == "N/A" || min_year == "N/A"
      crunch_set(max_year, min_year, subject, name, grade)
    end
  end

  def crunch_set(max_year, min_year, subject, name, grade)
    numerator = numerator(max_year, min_year, subject, name, grade)
    denominator = max_year - min_year
    [name, growth(numerator, denominator)]
  end

  def clean_and_return(result)
    result.compact!
    polished = result.map do |set|
      [set.first, Clean.three_truncate(set.last)]
    end
    return polished.sort_by {|set| set.last}
  end

  def growth(numerator, denominator)
    if numerator == 0 && denominator == 0
      0
    else
      numerator / denominator
    end
  end

  def numerator(max_year, min_year, subject, name, grade)
    district = @district_repository.districts[name].statewide_test
    max = district.send(grade)[max_year][subject]
    min = district.send(grade)[min_year][subject]
    if max == min
      return 0
    else
      max - min
    end
  end

  def validate_max_year(year, subject, name, grade)
    district = @district_repository.districts[name]
    if max_year_base_condition?(year, subject, grade, district)
      "N/A"
    elsif district.statewide_test.send(grade)[year][subject].is_a?(Float)
      year
    else
      validate_max_year((year - 1), subject, name, grade)
    end
  end

  def min_year_base_condition?(year, subject, grade, district)
    year == 2014 &&
      district.statewide_test.send(grade)[year][subject] == "N/A"
  end

  def max_year_base_condition?(year, subject, grade, district)
    year == 2008 &&
      district.statewide_test.send(grade)[year][subject] == "N/A"
  end

  def validate_min_year(year, subject, name, grade)
    district = @district_repository.districts[name]
    if min_year_base_condition?(year, subject, grade, district)
      "N/A"
    elsif district.statewide_test.send(grade)[year][subject].is_a?(Float)
      year
    else
      validate_min_year((year + 1), subject, name, grade)
    end
  end

  def kindergarten_participation_rate_variation(name, against)
    numerator = calculate(name, "kindergarten_participation")
    denominator = calculate(against[:against], "kindergarten_participation")
    variation = (numerator / denominator).round(3)
  end

  def kindergarten_participation_rate_variation_trend(name, against)
    numerator = kindergarten_participation_finder(name)
    denominator = kindergarten_participation_finder(against[:against])
    variation_trend_calculator(numerator, denominator)
  end

  def kindergarten_participation_finder(name)
    numerator = @district_repository.
      find_by_name(name).enrollment.kindergarten_participation
  end

  def kindergarten_participation_against_high_school_graduation(name)
    numerator = kindergarten_participation_rate_variation(name,
      :against => "COLORADO")
    denominator = calculate(name, "high_school_graduation") /
                  calculate("COLORADO", "high_school_graduation")
    variation = (numerator / denominator).round(3)
  end

  def kindergarten_participation_correlates_with_high_school_graduation(name)
    if name.keys[0] == :for
      correlates_for(name[:for])
    elsif name.keys[0] == :across
      correlates_across(name[:across])
    end
  end

  def correlates_for(name)
    name == "STATEWIDE" ? statewide_correlation : districts_correlation(name)
  end

  def correlates_across(districts)
    results = districts.reduce(0) do |sum, district|
      sum += 1 if
      validator(kindergarten_participation_against_high_school_graduation(district))
    end
    return group_validator(results / districts.count)
  end

  def calculate(name, type)
    years = @district_repository.find_by_name(name).enrollment.send(type)
    sum = years.reduce(0) do |sum, (key,value)|
      sum + years[key]
    end
    average = Clean.three_truncate(sum / years.count)
  end

  def variation_trend_calculator(numerator, denominator)
    result = {}
    numerator.each do |key,value|
      result[key] = Clean.three_truncate(numerator[key]/denominator[key])
    end
    result
  end

  def districts_correlation(name)
    variation = kindergarten_participation_against_high_school_graduation(name)
    validator(variation)
  end

  def statewide_correlation
    sum = 0
    @district_repository.districts.each do |key, value|
      sum += 1 if
      validator(kindergarten_participation_against_high_school_graduation(key))
    end
    variation = sum.to_f / @district_repository.districts.count
    group_validator(variation)
  end

  def group_validator(variation)
    variation >= 0.70 ? true : false
  end

  def validator(variation)
    variation >= 0.6 && variation <= 1.5 ? true : false
  end

end
