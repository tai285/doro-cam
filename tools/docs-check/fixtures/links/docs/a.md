# Title A
## Section — One
[ok](b.md)
[ok anchor](b.md#target-heading)
[bad file](missing.md)
[bad anchor](b.md#nope)
[self ok](#section--one)
[self bad](#absent)
[dir ok](sub/)
[escape](../../outside.md)
[external](https://example.com/x) and [mail](mailto:someone@example.com)
[anchor on dir](sub/#x)
`[code span](missing-in-code.md)`
```
[fenced](missing-in-fence.md)
```
![image](img/missing.png)
[percent ok](b%2Emd)
[bad percent](b%E0.md)

[ref]: ref-missing.md
