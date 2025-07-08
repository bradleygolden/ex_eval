ExUnit.start(exclude: [:skip])

Application.put_env(:ex_eval, :reporter, ExEval.SilentReporter)

# Suppress application lifecycle logs during tests
Logger.configure(level: :error)
