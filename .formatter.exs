# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test,examples}/**/*.{ex,exs}"],
  locals_without_parens: [
    # ExEval evaluation macros
    eval_dataset: 1,
    dataset_setup: 1
  ],
  export: [
    locals_without_parens: [
      eval_dataset: 1,
      dataset_setup: 1
    ]
  ]
]
