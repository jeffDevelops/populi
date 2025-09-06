# Populi - A metaframework for decentralized applicationsEX

Populi is a metaframework for decentralized applications. It is not open source. Here's why:

Traditional open source assumes good faith and shared values. Some actors, however, have fundamentally hostile interests we believe actively must be excluded. We are open to participation, but have mechanisms to exclude bad-faith actors who would destroy the system from within.

## Big Tech's Open Source Playbook

### Embrace, Extend, Extinguish
FAANG (Facebook, Amazon, Apple, Netflix, Google), or now MANGA (Meta / Microsoft, Amazon, Netflix, Google, Apple) have used open source to fragment networks and kill alternatives. 

Historical examples of this playbook include XMPP, RSS, and email. Google embraced and extended XMPP with Google Talk, then abandoned the project, fragmenting the network. Facebook and Twitter killed adoption of RSS by providing "better" proprietary alternatives. Email still uses open protocols but is increasingly controlled by Gmail/Outlook oligopoly.

#### Embrace
FAANG: "Sure! We support open standards! We'll build clients that work with your protocol. We'll even contribute to development and provide infrastructure, if you allow us to gain influence in governance."

#### Extend
FAANG then add proprietary features that only work with their clients. "We provide an enhanced experience when connecting to other \[FAANG\] users." This gradually makes the underlying protocol inferior and less interoperable with other protocols.

#### Extinguish
FAANG achieves a critical mass of users dependent on the proprietary experience. They break compatibility with implementations that use the "pure" open standard, and use colorful language like "legacy" to describe those implementations to portray them as inferior. They then force users to choose between losing the features they provide, or switch to the corporate version with the subscription plan.

### Vendor Lock-in Patterns
- Tech companies offer "free" services that are often critical dependencies, such as authentication, database hosting, etc., and build their business models off the idea that many of these free tier accounts will upgrade to paid accounts once usership grows. Sure, these companies need to make money, but the price gouge that comes with consumers' broaching the paid tier is often prohibitive to the point where the fledgling service either needs the resources to spend a development cycle on migrating to an in-house replacement, or be forced to shutter the service entirely.

### Other potential Big Tech attack vectors

#### Infrastructure Capture
- In exchange for governance influence, FAANG could offer "free" high-performing signaling, STUN, and TURN servers that increasingly become dependencies.
- Storage: FAANG could offer "free" cloud storage in OneDrive, Google Drive, iCloud, or S3, or bundle such services with their proprietary clients.

#### Superior Engineering Resources
- FAANG has access to some of the best engineers in the world, and can use their influence to recruit top talent. This gives them a significant advantage in development speed and quality.