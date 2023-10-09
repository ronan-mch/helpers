#!/usr/bin/env ruby

def avg_duration(workflow)
  runs = successful_runs(workflow)
  avg_dur = runs.map(&:time).inject(&:+) / runs.size
  puts "Avg duration for #{workflow}: #{avg_dur}s"
end

SuccessfulRun = Struct.new(:time, :run_id) do
end

def successful_runs(workflow)
  runs_output = `gh workflow view #{workflow} | grep success`
  runs = []
  runs_output.each_line do |line|
    fields = line.split("\t")
    time = fields[6].scan(/\d+/).inject { |m,s| (m.to_i*60) + s.to_i }
    run_id = fields[7].to_i
    runs << SuccessfulRun.new(time, run_id)
  end
  runs
end

def execute(cmd)
  `#{cmd}`.split("\n")
end

def get_logs(job_id)
  execute("gh run view --job=#{job_id} --log")
end

def logs(workflow)
  Dir.mkdir("logs") if !Dir.exist?("logs")

  successful_runs(workflow).each do |run|
    job_ids = execute("gh run view #{run.run_id} --json jobs -q '.jobs[].databaseId'").map(&:to_i)
    job_ids.each do |job_id|
      logfile = get_logs(job_id)
      fname = "logs/#{job_id}.log"
      puts "Writing #{fname}"
      File.new(fname, "w").write(logfile.join("\n"))
    end
  end
end

LogLine = Struct.new(:job, :step, :timestamp, :log, :duration)

def analyse_log(logfile)
  loglines = []
  File.open(logfile).each_line do |line|
    job, step, mixed = line.split("\t")
    ts, log = mixed.split("Z ")
    timestamp = Time.new(ts)
    loglines << LogLine.new(job, step, timestamp, log.chomp)
  end
  loglines.each.with_index do |logline, i|
    if next_line = loglines[i+1]
      duration = next_line.timestamp - logline.timestamp
      logline.duration = duration
    end
  end
  profiled_steps = loglines
    .group_by(&:step)
    .each_with_object({}) do |(step, loglines), h|
      h[step] = loglines.last.timestamp - loglines.first.timestamp
    end
      .sort_by { |_, duration| duration }
      .reverse

  puts "Steps in order of duration"
  profiled_steps.each do |step, duration|
    puts "Step: #{step} | Duration: #{duration}"
  end
  puts "+" * 20

  top_ten = loglines[0..-2]
    .sort_by(&:duration)
    .reverse
    .take(10)
  puts "Top 10 actions:"
  top_ten.each.with_index do |logline, idx|
    puts "#{idx+1} - #{logline.log} - #{logline.duration}"
  end
  puts "+" * 20
end

cmd = ARGV[0]
target = ARGV[1]
case cmd
when "duration"
  avg_duration(target)
when "logs"
  logs(target)
when "analyse"
  analyse_log(target)
else
  raise "#{cmd} is not a valid command"
end

