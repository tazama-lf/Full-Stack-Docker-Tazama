Hi Team,

The beta sandbox launch is delayed. Our revised target is Friday, 17 April. Details below.

Over the last two weeks the Product team have spent significant time trying to get our release ready for beta testing. On Thursday, we announced the public beta testing to the community with the expectation that we would be able to deploy a sandbox by Monday, based on the status of project delivery. Our view was that most of the outstanding work was on our side to automate the build of the platform via Docker Compose and then deploy the platform onto AWS.

## Current State:

Over the weekend, we discovered that the platform readiness was greatly exaggerated. The Docker Compose deployment repo we received was incomplete (it did not cover all required components, some components were deployed from feature branches, and the overall structure of the Docker Compose configuration was lacking and in some cases incorrect), and not all components were finalised according to our expectations. For example, the CMS source code in the repository was incapable of building due to a package dependency mismatch and there are currently three major unmerged PRs in the repository.

A number of issues were raised with Paysys over Slack yesterday. These issues are blockers for the beta sandbox deployment. We have had several sessions with Paysys today to close the gaps so that we can have our sandbox up and running as soon as possible, but at the time of writing the deployment is delayed. I have a commitment from Paysys that the gaps will be closed by end of day today.

## Contributing factors:

 - Our capacity for "hands-on" oversight on project deliverables is severely constrained. We have relied on Paysys project feedback in standups and demos to assess the progress on the delivery of all milestones and there has been no indication of this outcome to date.
 - Paysys themselves reported a working end-to-end sandbox and constant UAT and refinement. This gave us the impression that they had a working instance of the platform up and running and that a transition to a Tazama-deployed and -operated instance would be reasonably trivial.
 - Milestones and tasks on GitHub that are used to track the project delivery are largely completed. There are very few outstanding tasks on the board, and none of the gaps we identified have been reported elsewhere.
 - It should be noted that the volume of features, components and functionality deployed in this release is vast and some gaps and shortfalls are inevitable, but the more significant concern is in the lack of transparency or accuracy in the reporting of the actual state.

## Impact:

 - We have not yet had any requests from our community for access to the sandbox for any of their users - we communicated this as the initial step towards participation on Thursday. This buys us a little time in launching the actual sandbox and the community is not directly applying any immediate pressure on the availability of the sandbox.
 - The biggest impact is on the Delta Analytics team. Sandy is in the process of documenting our requirements as requested and we should be able to send them some of the specifications today, but the sandbox itself will not be available for them to use today. We have an email from Jai requesting a status update and I will have to notify them that we are unavoidably delayed until Friday to accommodate any further unforeseen delays. At this time, given the misrepresentation of the state of the delivery, and the pattern of issues surfacing during inspection, my confidence in meeting a sooner deadline is low and I'd rather add a risk buffer so that we don't have to communicate a second delay.

### Proposed action:

 - Move the target date for the sandbox to Friday
 - Delta Analytics:
   - Communicate the delay to Delta Analytics immediately (today)
   - Send the requirements specifications that we have starting tomorrow and as they become available over the rest of the week
 - Community:
   - Communicate a delay in the availability of the sandbox and a reminder to send through access details and nominated users in the meantime.

Regards,
Justus