defmodule Some do
	require Events
	def demo do
		#Events.new(%{execute_strategy: 10000}) do
		#	IO.puts "HELLO"
		#end
		Events.new(%{execute_strategy: [%{sec: 30}] }) do
			IO.puts Exutils.make_verbose_datetime
		end
	end
end