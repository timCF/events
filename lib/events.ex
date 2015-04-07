defmodule Events do
  use Application
  require Exutils
  use Hashex, [
                Events.Unit.State,
                Events.Message,
                Events.AccurateTime,
                Events.State
              ]
  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    :pg2.create("__my_events__")

    children = [
      # Define workers and child supervisors to be supervised
      # worker(Events.Worker, [arg1, arg2, arg3])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Events.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defmodule Message do
    defstruct eventid: "", subject: "", content: nil
  end
  # here fields int or nil if this opt is unused
  defmodule AccurateTime do
    defstruct year: nil, month: nil, day: nil, hour: nil, minute: nil, sec: nil
  end
  defmodule State do
    defstruct eventid: "", 
              repeat: :permanent, # | :once
              period: 0,
              stamp: 0,
              accurate_time: nil,
              callback: nil,
              user_state: nil
  end


  ##############
  ### public ###
  ##############

  def new(opts, callback) when ( is_map(opts) and is_function(callback, 1) ) do
    get_execute_strategy(opts)
      |> get_repeat_strategy(opts)
        |> HashUtils.set(:callback, callback)
          |> HashUtils.set(:user_state, HashUtils.get(opts, :state))
            |> create_event_process
  end
  def delete(eventid) when is_binary(eventid) do
    :pg2.get_members("__my_events__")
      |> Enum.each( fn(event) -> send(event, %Events.Message{eventid: eventid, subject: "delete", content: nil}) end )
  end

  ############
  ### priv ###
  ############

  @fields [:year, :month, :day, :hour, :minute, :sec]

  defp get_execute_strategy(opts) do
    case HashUtils.get(opts, [:execute_strategy]) do
      num when ( is_integer(num) and num > 0 ) -> %Events.State{eventid: Exutils.makecharid, period: num, stamp: Exutils.makestamp}
      _ -> case HashUtils.get(opts, [:execute_strategy]) do
          map when is_map(map) -> %Events.State{eventid: Exutils.makecharid, accurate_time: get_accurate_time(map)}
          _ -> raise "Events : No any valid execute strategy."
        end
    end
  end
  defp get_accurate_time(map) when is_map(map) do
    Enum.reduce(  [:year, :month, :day, :hour, :minute, :sec], 
      %Events.AccurateTime{},
      fn(field, res) ->
        case HashUtils.get(map, field) do
          num when (( is_integer(num) and (num >= 0) ) or (num == nil)) -> HashUtils.set(res, field, num)
          val -> raise "Events : wrong execute parameter #{inspect field} with value #{inspect val}."
        end
      end )
    |> check_accurate_time
      |> apply_defaults
        |> check_transform_to_greg_sec
  end
  defp check_accurate_time(%Events.AccurateTime{year: nil, month: nil, day: nil, hour: nil, minute: nil, sec: nil}) do
    raise "Events : No any execute strategy."
  end
  defp check_accurate_time(res = %Events.AccurateTime{year: year, month: month, day: day, hour: hour, minute: minute, sec: sec}) do
    case    ( (year > 2013) or (year == nil) ) and
        ( (month in 1..12) or (month == nil) ) and
        ( (day in 1..31) or (day == nil) ) and
        ( (hour in 0..23) or (hour == nil) ) and
        ( (minute in 0..59) or (minute == nil) ) and
        ( (sec in 0..59) or (sec == nil) ) do
    true -> res
    false -> raise "Events : wrong parameter in #{inspect res}"
    end
  end
  defp check_transform_to_greg_sec(res = %Events.AccurateTime{}) do
    %Events.AccurateTime{year: year, month: month, day: day, hour: hour, minute: minute, sec: sec} = HashUtils.modify_all( res, 
    fn(el) ->
      case el do
        nil -> 1
        _ -> el
      end
    end )
    case {{year, month, day},{hour, minute, sec}} |> :calendar.datetime_to_gregorian_seconds |> Exutils.safe do
      {:exit, reason} -> raise "Events : incorrect date in accurate_time. #{inspect(reason)}"
      _ -> res
    end
  end
  defp apply_defaults(input = %Events.AccurateTime{}) do
    first_not_null = Enum.reduce( @fields, nil, 
    fn(field, res) ->
      case res do
        nil ->  case HashUtils.get(input, field) do
              nil -> nil
              _ -> Enum.find_index(@fields, &(&1 == field))
            end
        some -> some
      end
    end )
    Enum.drop( @fields, (first_not_null+1) )
      |> Enum.reduce( input, 
        fn(field, input) ->
          case HashUtils.get(input, field) do
            nil -> HashUtils.set(input, field, default_field(field))
            _ -> input
          end
        end )
  end
  defp default_field(field) do
    case field do
      :year -> raise "Events : can't set year by default!"
      :month -> 1
      :day -> 1
      :hour -> 0
      :minute -> 0
      :sec -> 0
    end
  end



  defp get_repeat_strategy(res = %Events.State{}, opts) do
    case HashUtils.get(opts, :repeat) do
      nil -> HashUtils.set(res, :repeat, :permanent)
      :permanent -> HashUtils.set(res, :repeat, :permanent)
      :once -> HashUtils.set(res, :repeat, :once)
    end
  end


  defp create_event_process(state = %Events.State{eventid: eventid}) do
    :ok = :supervisor.start_child( Events.Supervisor, Supervisor.Spec.worker(Events.Unit, [state], [id: eventid,  restart: :transient])) |> elem(0)
    eventid
  end

end
