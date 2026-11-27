/// Built-in note templates. {{date}} is replaced with today's date.
class NoteTemplate {
  const NoteTemplate(this.name, this.icon, this.title, this.body);
  final String name;
  final String icon;
  final String title;
  final String body;
}

const templates = <NoteTemplate>[
  NoteTemplate('Blank note', '📝', '', ''),
  NoteTemplate('Sermon outline', '📖', 'Sermon: ', '''# Sermon: Title

**Date:** {{date}}  
**Text:** Book 0:0-0  
**Venue / Service:**  

## Big idea
One sentence that the congregation should remember.

## Introduction
- Hook / story
- Why this matters today

## I. First point
- Explanation
- Illustration
- Application

## II. Second point
- Explanation
- Illustration
- Application

## III. Third point
- Explanation
- Illustration
- Application

## Conclusion and call to response
- Summary
- Invitation / altar call

## Prayer points
- [ ] 
'''),
  NoteTemplate('Lesson plan', '🎓', 'Lesson plan: ', '''# Lesson plan: Topic

**Subject / Course:**  
**Date:** {{date}}  
**Duration:** 60 minutes  
**Class / Section:**  

## Learning objectives
By the end of the lesson, students will be able to:
1. 
2. 
3. 

## Materials
- 

## Procedure
| Time | Activity | Notes |
|------|----------|-------|
| 5 min | Motivation / opener | |
| 20 min | Discussion | |
| 20 min | Activity | |
| 10 min | Generalization | |
| 5 min | Assessment | |

## Assessment
- 

## Assignment
- [ ] 
'''),
  NoteTemplate('Meeting minutes', '🗂️', 'Minutes: ', '''# Minutes: Meeting name

**Date:** {{date}}  
**Time started:**  
**Presiding:**  
**Recorded by:**  

## Attendance
- Present:
- Absent:

## Opening prayer
- 

## Agenda
1. 
2. 
3. 

## Discussion and decisions
- 

## Action items
- [ ] Task — person @due({{date}})

## Adjournment
**Time ended:**  
**Closing prayer:**  
'''),
  NoteTemplate('Bible study', '✝️', 'Bible study: ', '''# Bible study: Passage

**Date:** {{date}}

## Read
Passage:

## Observe
- What does it say?

## Interpret
- What does it mean?

## Apply
- What will I do?

## Pray
- 
'''),
  NoteTemplate('To-do list', '✅', 'To-do', '''# To-do

- [ ] 
- [ ] 
- [ ] 
'''),
  NoteTemplate('Daily journal', '🌅', 'Journal {{date}}', '''# {{date}}

## Grateful for
- 

## Today's focus
- [ ] 

## Notes
'''),
];
