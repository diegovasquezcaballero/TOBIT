# **Codebook – `data_final_FLORIDA`**

## **1. Dataset Overview**

- Each **row** represents **one participant**.
- The dataset includes:
  - **Sociodemographic variables**
  - **Attention checks**
  - **IRI empathy items renamed by subscale**
  - **Treatment order**
  - **Scenario-level experimental variables for 10 stages (`s1` to `s10`)**

---

## **2. Sociodemographic Variables**

- **Participant ID (`id`)**  
  Consecutive identifier assigned to each participant.

- **Commitment check (`commitment`)**  
  Initial question included to encourage more candid responses.

  **Coding**
  - `0` = I do not commit
  - `1` = Yes, I commit
  - `2` = I cannot promise it

- **Age (`age`)**  
  Age in completed years.

- **Socioeconomic status (`economic_status`)**  
  Socioeconomic stratum based on DANE categories.

  **Coding**
  - `0` = Rural
  - `1` = Stratum 1
  - `2` = Stratum 2
  - `3` = Stratum 3
  - `4` = Stratum 4
  - `5` = Stratum 5
  - `6` = Stratum 6

- **Sex assigned at birth (`sex`)**

  **Coding**
  - `0` = I prefer not to say
  - `1` = Woman
  - `2` = Man
  - `3` = Intersex

- **Participant faculty affiliation (`faculty_player`)**

  **Coding**
  - `1` = Humanities
  - `2` = Engineering

---

## **3. Attention Checks**

- **Attention check 1 (`ac1`)**

  **Coding**
  - `0` = Wrong
  - `1` = Right

- **Attention check 2 (`ac2`)**

  **Coding**
  - `0` = Wrong
  - `1` = Right

---

## **4. Psychological Variables (IRI)**

**Important note**

- Reverse-worded items were already recoded correctly before this final dataset was created.
- Items are scored from **0 to 4**.
- Higher values indicate **higher empathy**.

### **IRI Subscales**

- **FS** = Fantasy
- **EC** = Empathic Concern
- **PT** = Perspective Taking
- **PD** = Personal Distress

### **IRI Item Structure**

```text
FS1
EC2
PT3
EC4
FS5
PD6
FS7
PT8
EC9
PD10
PT11
FS12
PD13
EC14
PT15
FS16
EC17
PD18
EC19
FS20
PT21
PD22
PT23
EC24
FS25
PT26
PD27
EC28
```

---

## **5. Treatment Variable**

- **Treatment order (`treatment`)**

Each participant evaluates **10 scenarios**:
- **5 as victim**
- **5 as observer**

To balance order effects, participants are randomly assigned to one of two sequences.

**Coding**
- `1` = Victim first, observer second
- `2` = Observer first, victim second

---

## **6. Scenario-Level Variables**

Each participant evaluates **10 stages (`s1` to `s10`)**.

In each stage, the variables are ordered as follows:

```text
faculty_neg_1_sX
faculty_neg_2_sX
faculty_victim_sX
decision_neg1_sX
decision_neg2_sX
judgement_compare_sX
judgement_n1_sX
judgement_n2_sX
```

where **`sX` refers to `s1` through `s10`**.

---

## **7. Coding of Scenario-Level Variables**

### **7.1 Faculty of Negotiator 1**
Variables:
- `faculty_neg_1_s1` to `faculty_neg_1_s10`

### **7.2 Faculty of Negotiator 2**
Variables:
- `faculty_neg_2_s1` to `faculty_neg_2_s10`

**Coding for both negotiator faculty variables**
- `1` = Humanities
- `2` = Engineering
- `3` = Control (no faculty label shown)

---

### **7.3 Faculty of Victim**
Variables:
- `faculty_victim_s1` to `faculty_victim_s10`

**Coding**
- `1` = Humanities
- `2` = Engineering

---

### **7.4 Decision of Negotiator 1**
Variables:
- `decision_neg1_s1` to `decision_neg1_s10`

### **7.5 Decision of Negotiator 2**
Variables:
- `decision_neg2_s1` to `decision_neg2_s10`

**Coding for both decision variables**
- `0` = Reject
- `1` = Accept

---

### **7.6 Comparative Moral Judgment**
Variables:
- `judgement_compare_s1` to `judgement_compare_s10`

**Coding**
- `1` = Negotiator 1 acted worse
- `2` = Negotiator 2 acted worse
- `3` = Both acted equally

---

### **7.7 Numerical Moral Judgment for Negotiator 1**
Variables:
- `judgement_n1_s1` to `judgement_n1_s10`

### **7.8 Numerical Moral Judgment for Negotiator 2**
Variables:
- `judgement_n2_s1` to `judgement_n2_s10`

**Scale**
- `-9` = Acted very badly
- `0` = Neutral midpoint
- `9` = Acted very well

---

## **8. Dataset Structure**

- Each **row** = one participant
- Each participant evaluates **10 scenarios**
- Each scenario includes **2 negotiators**
- Therefore, each participant provides:
  - **10 comparative judgments**
  - **10 ratings for Negotiator 1**
  - **10 ratings for Negotiator 2**

This means the dataset is currently in **wide format**, with repeated scenario-level variables stored across columns.

---

## **9. Variables by Analytical Level**

### **Participant-level variables**

```text
id
commitment
age
economic_status
sex
faculty_player
ac1
ac2
FS1
EC2
PT3
EC4
FS5
PD6
FS7
PT8
EC9
PD10
PT11
FS12
PD13
EC14
PT15
FS16
EC17
PD18
EC19
FS20
PT21
PD22
PT23
EC24
FS25
PT26
PD27
EC28
treatment
```

### **Scenario-level variables**

```text
faculty_neg_1_sX
faculty_neg_2_sX
faculty_victim_sX
decision_neg1_sX
decision_neg2_sX
judgement_compare_sX
judgement_n1_sX
judgement_n2_sX
```

where **`sX` refers to stages `s1` to `s10`**.
