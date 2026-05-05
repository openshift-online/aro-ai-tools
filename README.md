# aro-ai-tools

## Tools

### Ops Plugin

- Easy access to metrics and logs for ARO HCP (and Classic, WIP).
- Compatible with all agents and OSes.
- Zero-setup, just make sure you're `az`-logged into the appropriate tenant.

#### Installation

```
/plugin marketplace add openshift-online/aro-ai-tools
/plugin install ops@aro-ai-tools
```

Now reload plugins / restart agent and ask it, e.g. "which aro hcp kusto instances can I query".

Note: **It's a very good idea to enable marketplace autoupgrade — agents tend not to do that**.

### Standalone Skills

All skills, whether part of a plugin or not, can be installed on their own.

1. Run the skills installer
   ```
   npx skills@latest add openshift-online/aro-ai-tools
   ```
2. Pick the skills and agents you want.
3. Done (`npx skills --help` for more).


## Contributing

The lifecycle of a skill is split into two parts

### Standalone Skill

1. You do something.
2. You make a skill of it.
3. You use the skill multiple times and refine it.
4. You have the thought that it might be of use to others.
5. You send in a PR adding the skill into the `skills/` directory.

If *you* found it useful enough to refine how it works, who knows, maybe others will.

Things to consider:
- Was this a temporary task or something people will be doing long term (and therefore maintaining a skill for it makes sense).
- How hard is it to use? Will it work immediately or do people need to set up elaborate environments first.
- How hard is it to review? Is it a large verbose black box or can it be reviewed in under a minute by people wondering if they'd like to try it out? (See [grill-me](https://github.com/mattpocock/skills/blob/main/skills/productivity/grill-me/SKILL.md) for the gold standard.)
- (A common theme of all the points above is – what's the chance anyone other than you will actually take the time to install your skill and then use it more than once.)
- Will you maintain it? If a PR comes in, will you review it?

### Plugin Skill

The bar is considerably higher here.

1. Your skill is being used by multiple people and forms a basis of a common workflow.
2. Those people agree it should be available out of the box in a plugin.
3. At this point you can send in a PR to move your skill into a plugin (or to create a new plugin if interested parties agree to use it).


