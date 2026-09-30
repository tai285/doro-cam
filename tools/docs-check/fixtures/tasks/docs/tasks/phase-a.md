# Phase A

### AAA-T-001 Valid root task
- **Status:** done
- **Depends:** none
- **Requirements:** CAM-001
- **Acceptance:** works

### AAA-T-002 Missing fields and bad status
- **Status:** started
- **Requirements:** CAM-001

### AAA-T-003 Unknown things
- **Status:** blocked
- **Depends:** AAA-T-001, AAA-T-999, not-a-task
- **Requirements:** CAM-001, CAM-404, depends on CAM-T-001 only
- **Acceptance:** n/a

### AAA-T-004 Done too early
- **Status:** done
- **Depends:** AAA-T-005
- **Requirements:** CAM-002
- **Acceptance:** ok

### AAA-T-005 Cycle start
- **Status:** todo
- **Depends:** AAA-T-006
- **Requirements:** CAM-002
- **Acceptance:** ok

### AAA-T-006 Cycle end
- **Status:** blocked (waiting on hardware)
- **Depends:** AAA-T-005
- **Requirements:** CAM-002
- **Acceptance:** ok
- **Acceptance:** repeated

### AAA-T-007
- **Status:** todo
- **Depends:** AAA-T-007
- **Requirements:** no ids here
- **Acceptance:** ok

### AAA-T-08 Malformed id
- **Status:** todo

```
### AAA-T-009 Inside a fence is ignored
```
