# Local Discussion coordination Action

This is an owner-authorized public copy of the newly authored Pantheon helper,
composite Action and tests. It runs directly in Cadence without fetching private
code or requiring private-repository credentials. See the
[setup guide](../../../docs/GITHUB-DISCUSSIONS.md) and [protocol](PROTOCOL.md).

Upstream source revision: `c07f700d375acf8cd2e5be6a93983c118575ef75` in
`madhakish/pantheon`, directory `integrations/github/`.
[Source commit](https://github.com/madhakish/pantheon/commit/c07f700d375acf8cd2e5be6a93983c118575ef75)
requires access to that private repository. The local copy is fully usable here.

| Exact copied file | SHA-256 |
| --- | --- |
| `coord.py` | `d99ce4a68a3aed0b4eb384d9588bd865c7abed135216aab72e7b1234389132d6` |
| `test_coord.py` | `acb900db6566198ee27caaa96f04c4ee0f7cd7b01350406a5fe042b3f5345391` |
| `action.yml` | `c7da93c266c66e403bd98cab42f9dc018c21b62b82921bde44844151a1ff01c2` |

For updates, copy only the reviewed helper, Action and tests from an authorized
Pantheon checkout. Update the revision/hashes and run the tests in the same PR.
The protocol has only its root-relative link adapted; setup/workflow guidance is
local. Never copy credentials, session state or private task content.

```sh
python3 -m unittest discover -s .github/actions/agent-directory -p 'test_*.py' -v
python3 .github/actions/agent-directory/coord.py --help
```
