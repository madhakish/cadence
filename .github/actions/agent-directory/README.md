# Local Discussion coordination Action

This is an owner-authorized public copy of the newly authored Pantheon helper,
composite Action and tests. It runs directly in Cadence without fetching private
code or requiring private-repository credentials. See the
[setup guide](../../../docs/GITHUB-DISCUSSIONS.md) and [protocol](PROTOCOL.md).

Upstream source revision: `a6e644b17d80218cac7894c7d034c29b1cebe8cb` in
`madhakish/pantheon`, directory `integrations/github/`.
[Source commit](https://github.com/madhakish/pantheon/commit/a6e644b17d80218cac7894c7d034c29b1cebe8cb)
requires access to that private repository. The local copy is fully usable here.

| Exact copied file | SHA-256 |
| --- | --- |
| `coord.py` | `fc3b375e7e0a5851436bea10f8ac8b76660e153dcb22a1f217b669590d6181fa` |
| `test_coord.py` | `96b391782e162ac670a443e78790ea918ea4af7cf13245c1cb6e0cc988ba34f5` |
| `action.yml` | `c7da93c266c66e403bd98cab42f9dc018c21b62b82921bde44844151a1ff01c2` |

For updates, copy only the reviewed helper, Action and tests from an authorized
Pantheon checkout. Update the revision/hashes and run the tests in the same PR.
The protocol has only its root-relative link adapted; setup/workflow guidance is
local. Never copy credentials, session state or private task content.

```sh
python3 -m unittest discover -s .github/actions/agent-directory -p 'test_*.py' -v
python3 .github/actions/agent-directory/coord.py --help
```
