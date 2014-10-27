defmodule Some do
	require Events
	def demo do
		#Events.new(%{execute_strategy: 10000}) do
		#	IO.puts "HELLO"
		#end
		Events.new(%{execute_strategy: %{sec: 30}, state: 1}, 
			fn(state) ->
				IO.puts "call with state #{state}, when #{inspect(:os.timestamp |> :calendar.now_to_datetime)}"
				state + 1
			end )
	end
end