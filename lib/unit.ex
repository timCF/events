defmodule Events.Unit do
	use ExActor.GenServer
	require Logger
	@fields [:year, :month, :day, :hour, :minute, :sec]
	@new_fields_values %{month: 1, day: 1, hour: 0, minute: 0, sec: 0}

	defmodule State do
		@derive [HashUtils]
		defstruct 	datetime: nil,
					field: nil,
					nowsec: nil
	end

	definit state = %Events.State{} do
		:pg2.join( "__my_events__", self )
		Logger.info "Event initialized! #{inspect state}"
		{:ok, state, get_sleeptime(state)}
	end
	definfo :timeout, state: state = %Events.State{callback: callback, period: 0, stamp: 0, repeat: repeat} do
		Logger.debug "Event : callback by accurate_time! #{inspect state}"
		callback.()
		case repeat do
			:permanent -> {:noreply, state, get_sleeptime(state)}
			:once -> 	Logger.warn "Event : called ounce, will terminate!"
						{:stop, :normal, state}
		end
	end
	definfo :timeout, state: state = %Events.State{callback: callback, repeat: repeat} do
		Logger.debug "Event : callback by period! #{inspect state}"
		callback.()
		new_state = HashUtils.set(state, :stamp, Exutils.makestamp)
		case repeat do
			:permanent -> {:noreply, new_state, get_sleeptime(new_state)}
			:once -> 	Logger.warn "Event : called ounce, will terminate!"
						{:stop, :normal, new_state}
		end
	end
	definfo %Events.Message{eventid: eventid, subject: "delete"}, state: state = %Events.State{eventid: eventid} do
		Logger.warn "Event : got delete signal, terminate!"
		{:stop, :normal, state}
	end


	defp get_sleeptime(%Events.State{period: period, stamp: stamp, accurate_time: nil}) do
		case (period - (Exutils.makestamp - stamp)) do
			num when ( num > 0 ) -> num
			_ -> 0
		end
	end
	defp get_sleeptime(%Events.State{period: 0, stamp: 0, accurate_time: lst}) when is_list(lst) do
		nowsec = :os.timestamp |> :calendar.now_to_datetime |>  :calendar.datetime_to_gregorian_seconds
		case Enum.map(lst, fn(el) -> %State{datetime: el, field: get_field_maybe_to_increment(el), nowsec: nowsec} end)
				|> Enum.map( fn(el) -> HashUtils.modify(el, :datetime, &set_needed_fields/1) end )
					|> Enum.map( fn(el) -> HashUtils.modify(el, :datetime, &fix_day_in_need/1) end )
						|> Enum.map( &maybe_increment/1 )
							|> Enum.filter(&( &1 >= nowsec ))  do
			[] -> :hibernate
			new_lst -> case (Enum.sort(new_lst) |> List.first) - nowsec do
							some when (some > 0) -> :timer.seconds(some)
							_ -> 0
						end
		end
	end
	defp set_needed_fields(input) do
		HashUtils.to_list(input)
			|> Enum.map(
				fn({key, val}) ->
					case val do
						nil -> {key, get_now(key)}
						val -> {key, val}
					end
				end )
			|> HashUtils.to_map
	end
	defp fix_day_in_need(input = %{year: year, month: month, day: day}) do
		case :calendar.last_day_of_the_month(year, month) do
			some_day when ( some_day < day ) -> HashUtils.set(input, :day, some_day)
			_ -> input
		end
	end
	defp get_field_maybe_to_increment(input = %Events.AccurateTime{}) do
		Enum.reduce(@fields, nil,
			fn(field, res) ->
				case HashUtils.get(input, field) do
					nil -> field
					_ -> res
				end
			end )
	end

	defp maybe_increment(%State{datetime: datetime, field: nil}) do
		datetime_to_seconds(datetime)
	end
	defp maybe_increment(%State{datetime: datetime, field: field, nowsec: nowsec}) do
		case datetime_to_seconds(datetime) do
			res when (res > nowsec) -> res
			_ -> increment_proc(datetime, field)
					|> datetime_to_seconds
		end
	end

	defp increment_proc(datetime = %{minute: minute}, :minute) do
		case minute do
			59 -> HashUtils.set(datetime, :minute, 0) |> increment_proc(:hour)
			_ -> HashUtils.set(datetime, :minute, minute+1)
		end 
	end
	defp increment_proc(datetime = %{hour: hour}, :hour) do
		case hour do
			23 -> HashUtils.set(datetime, :hour, 0) |> increment_proc(:day)
			_ -> HashUtils.set(datetime, :hour, hour+1)
		end 
	end
	defp increment_proc(datetime = %{year: year, month: month, day: day}, :day) do
		case :calendar.last_day_of_the_month(year, month) == day do
			true -> HashUtils.set(datetime, :day, 1) |> increment_proc(:month)
			false -> HashUtils.set(datetime, :day, day+1)
		end 
	end
	defp increment_proc(datetime = %{month: month}, :month) do
		case month do
			12 -> HashUtils.set(datetime, :month, 1) |> increment_proc(:year)
			_ -> HashUtils.set(datetime, :month, month+1)
		end 
	end
	defp increment_proc(datetime, :year) do
		HashUtils.modify(datetime, :year, &(&1+1))
	end

	defp datetime_to_seconds(%{year: year, month: month, day: day, hour: hour, minute: minute, sec: sec}) do
		{{year, month, day},{hour, minute, sec}}
			|> :calendar.datetime_to_gregorian_seconds
	end


	defp get_now(what) do
		{{year, month, day},{hour, minute, sec}} = :os.timestamp |> :calendar.now_to_datetime
		case what do
			:year -> year
			:month -> month
			:day -> day
			:hour -> hour
			:minute -> minute
			:sec -> sec
		end
	end

end