# Phase A

### AAA-T-001 Valid root task
- **Status:** done
- **Depends:** none
- **Requirements:** CAM-001
- **Acceptance:** works
- **Tests:** unit tests

### AAA-T-002 Missing fields and bad status
- **Status:** started
- **Requirements:** CAM-001

### AAA-T-003 Unknown things
- **Status:** blocked
- **Depends:** AAA-T-001, AAA-T-999, not-a-task
- **Requirements:** CAM-001, CAM-404, depends on CAM-T-001 only
- **Acceptance:** n/a
- **Tests:** n/a

### AAA-T-004 Done too early
- **Status:** done
- **Depends:** AAA-T-005
- **Requirements:** CAM-002
- **Acceptance:** ok
- **Tests:** integration test

### AAA-T-005 Cycle start
- **Status:** todo
- **Depends:** AAA-T-006
- **Requirements:** CAM-002
- **Acceptance:** ok
- **Tests:** n/a (spike measurement only). Results go to spikes.md.

### AAA-T-006 Cycle end
- **Status:** blocked (waiting on hardware)
- **Depends:** AAA-T-005
- **Requirements:** CAM-002
- **Acceptance:** ok
- **Acceptance:** repeated
- **Tests:**

### AAA-T-007
- **Status:** todo
- **Depends:** AAA-T-007
- **Requirements:** no ids here
- **Acceptance:** ok
- **Tests:** widget tests

### AAA-T-08 Malformed id
- **Status:** todo

```
### AAA-T-009 Inside a fence is ignored
```
