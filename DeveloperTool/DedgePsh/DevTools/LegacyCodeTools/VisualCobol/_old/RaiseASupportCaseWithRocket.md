# Preparing to Raise a Support Case

_Last Updated: Jun 27, 2025_

**Product:** Visual COBOL 11.0  
**Audience:** Developers, Users

---

We recommend following these guidelines when preparing to log a support case with Rocket Software.

---

## Information to Gather for All Support Cases

Provide the following essential information to Rocket Technical Support when creating any support case:

- **Rocket Software product serial number**
  - Locate this in the subject/body of your _Electronic Delivery Receipt_ email or _Rocket Software Activation Information_ email from Rocket Software.
- **Computer make and model**
  - This information is usually found on your physical machine.
- **Product and environment information**
  - The best way to collect this is by running the [Rocket Software Support Scan utility](#) (see documentation for usage and options to include its output in your support case).

---

## Details About Your Problem

When raising a support case, include:

- **Accurate subject line:** Briefly and precisely describe your problem.
  - **Examples:**
    - _Good:_  
      `Source won't compile, getting error code ###`  
      `Enterprise Server shows error code ### during restart`
    - _Not useful:_  
      `Error with source compile`  
      `Enterprise server is crashing`
- **Comprehensive problem description:**
    - Context for the problem
    - Your observations and knowledge
    - Step-by-step instructions for reproducing the problem
    - For compilation problems, specify any compiler directive options used
    - Additional details specific to your case type (see _Different Types of Cases_ for more)

---

## Additional Guidance for Different Problem Types

### Easily Reproducible Problems

For issues that reliably recur:

- Supply all information from the **All Support Cases** section above.
- Be ready to provide a **zipped copy of your project and/or source code** to enable Rocket Software to quickly reproduce the problem.

### Complex Problems

For infrequent or timing/random-related problems (often seen in production systems):

Follow all guidance above, _plus_:

- Add further detail to your description, including:
    - Chronology of the issue
    - Symptoms observed
    - Configuration specifications
    - Workload levels
    - Environmental factors and what else was happening at the time
    - Any third-party software involved
- Attach:
    - **A zipped archive** of the relevant source code as it existed when the problem occurred
    - **A zipped archive** of all pertinent first point-of-failure diagnostics files

> **Attention:** Failure diagnostics are critical; always provide them where possible. Consult _Diagnostics for COBOL Applications_ or _Diagnostics for Enterprise Server Applications_ for help with diagnostic tools.

**Best Practices for Diagnostics:**

- Include complete diagnostics (traces, dumps, console logs, and other relevant logs)
- Ensure logs for the same failure are provided _in chronological sequence_
- Information should be specific enough to identify the:
    - Exact failure
    - Date and time of failure
    - Demonstrated symptoms
    - Whether recovery occurred, and if so, if it was automatic or manual

---

For further details, see the _Raising and Managing Support Cases_ section, which explains how to create a support case and how Rocket Technical Support can assist with issue resolution.