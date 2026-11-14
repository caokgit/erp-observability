# Template: a learn section

A section in `docs/learn/<topic>.md`, written when the owner asks a question, with a row in the learn README's question
finder ([the rule](../METHOD.md#a-clarification-question-is-a-doc-bug)). Copy the block below.

````markdown
## <The concept, as a heading a reader can scan>

Asked on <YYYY-MM-DD>: "<the question, as the owner asked it>"

**<The one idea that explains everything, in one bold sentence.>**

<What it is and why it exists: its purpose here, in plain words before terms.>

<A diagram of the flow or the pieces (Mermaid, or a colour SVG in docs/learn/diagrams/).>

<One concrete thing followed through each case, with real values (REAL, dated); DOCS for vendor facts with their
source and date; PLANNED for what is not built; ILLUSTRATIVE only when no real value exists.>

| Case | <what changes> | <what it fixes> | <what it does not> |
|---|---|---|---|

**In our design:** [D<n>](../design.md#decisions) <how the design uses it>.
````
