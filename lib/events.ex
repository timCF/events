defmodule Events do
  use Application

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
    @derive [HashUtils]
    defstruct eventid: "", subject: "", content: nil
  end
  # here fields int or nil if this opt is unused
  defmodule AccurateTime do
    @derive [HashUtils]
    defstruct year: nil, month: nil, day: nil, hour: nil, minute: nil, sec: nil
  end
  defmodule State do
    @derive [HashUtils]
    defstruct eventid: "", 
              repeat: :permanent, # | :once
              period: 0,
              stamp: 0,
              accurate_time: nil,
              callback: nil,
              user_state: nil
  end

  use Events.Body

end
